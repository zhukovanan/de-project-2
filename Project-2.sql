--shipping
CREATE TABLE public.shipping(
   ID serial ,
   shippingid                         BIGINT,
   saleid                             BIGINT,
   orderid                            BIGINT,
   clientid                           BIGINT,
   payment_amount                          NUMERIC(14,2),
   state_datetime                    TIMESTAMP,
   productid                          BIGINT,
   description                       text,
   vendorid                           BIGINT,
   namecategory                      text,
   base_country                      text,
   status                            text,
   state                             text,
   shipping_plan_datetime            TIMESTAMP,
   hours_to_plan_shipping           NUMERIC(14,2),
   shipping_transfer_description     text,
   shipping_transfer_rate           NUMERIC(14,3),
   shipping_country                  text,
   shipping_country_base_rate       NUMERIC(14,3),
   vendor_agreement_description      text,
   PRIMARY KEY (ID)
);
CREATE INDEX shippingid ON public.shipping (shippingid);
COMMENT ON COLUMN public.shipping.shippingid is 'id of shipping of sale';


--shipping_country_rates
CREATE TABLE public.shipping_country_rates(
  ID                              serial,
  shipping_country                 text,
  shipping_country_base_rate       NUMERIC(14,3),
  PRIMARY KEY (ID));

--shipping_agreement
CREATE TABLE public.shipping_agreement(
  agreementid                              BIGINT,
  agreement_number                 text,
  agreement_rate       NUMERIC(14,3),
  agreement_commission NUMERIC(14,3),
  PRIMARY KEY (agreementid));

--shipping_transfer
CREATE TABLE public.shipping_transfer(
  id                             serial,
  transfer_type                 text,
  transfer_model       			text,
  shipping_transfer_rate NUMERIC(14,3),
  PRIMARY KEY (id));
  
--shipping_info
CREATE TABLE public.shipping_info(
  shippingid               BIGINT,
  vendorid                 BIGINT,
  payment_amount NUMERIC(14,2) ,
  shipping_plan_datetime  TIMESTAMP,
  transfer_type_id BIGINT,
  shipping_country_id BIGINT,
  agreementid BIGINT,
  PRIMARY KEY (shippingid),
  FOREIGN KEY (transfer_type_id) REFERENCES public.shipping_transfer(id),
  FOREIGN KEY (shipping_country_id) REFERENCES public.shipping_country_rates(id),
  FOREIGN KEY (agreementid) REFERENCES public.shipping_agreement(agreementid));
 
  
--shipping_status
CREATE TABLE public.shipping_status(
  shippingid               BIGINT,
  status                 text,
  state                  text,
  shipping_start_fact_datetime TIMESTAMP,
  shipping_end_fact_datetime  TIMESTAMP,
  PRIMARY KEY (shippingid));

  
--insert data into shipping_country_rates
insert into public.shipping_country_rates (shipping_country,shipping_country_base_rate)
select distinct
	shipping_country,
	shipping_country_base_rate
from public.shipping;


--insert data into shipping_agreement
insert into public.shipping_agreement (agreementid,agreement_number,agreement_rate,agreement_commission)
select distinct
	(regexp_split_to_array(vendor_agreement_description, E'\\:+'))[1]::int,
	(regexp_split_to_array(vendor_agreement_description, E'\\:+'))[2]::text,
	(regexp_split_to_array(vendor_agreement_description, E'\\:+'))[3]::numeric,
	(regexp_split_to_array(vendor_agreement_description, E'\\:+'))[4]::numeric
from public.shipping;


--insert data into shipping_transfer
insert into public.shipping_transfer (transfer_type,transfer_model,shipping_transfer_rate)
select distinct
	(regexp_split_to_array(shipping_transfer_description, E'\\:+'))[1]::text,
	(regexp_split_to_array(shipping_transfer_description, E'\\:+'))[2]::text,
	shipping_transfer_rate
from public.shipping;


--insert data into shipping_info
insert into public.shipping_info(shippingid,vendorid,payment_amount,shipping_plan_datetime,transfer_type_id,shipping_country_id,agreementid)
select distinct 
	shippingid,
  	vendorid,
  	payment_amount,
  	shipping_plan_datetime,
  	st.id as transfer_type_id,
  	scr.id as shipping_country_id,
  	(regexp_split_to_array(vendor_agreement_description, E'\\:+'))[1]::int as agreementid
from public.shipping s
inner join public.shipping_transfer st 
on (regexp_split_to_array(shipping_transfer_description, E'\\:+'))[1]::text = st.transfer_type 
and (regexp_split_to_array(shipping_transfer_description, E'\\:+'))[2]::text = st.transfer_model
inner join public.shipping_country_rates scr
on s.shipping_country  = scr.shipping_country;


--insert data into shipping_status
with status_mart as (
select 
	shippingid,
	max(case when state = 'booked' then state_datetime end)  as shipping_start_fact_datetime,
	max(case when state = 'recieved' then state_datetime end) as shipping_end_fact_datetime,
	max(state_datetime) as max_dat
from public.shipping s
where state in ('recieved', 'booked')
group by shippingid)


insert into public.shipping_status
select distinct
	s.shippingid,
	status,
	state,
	shipping_start_fact_datetime,
	shipping_end_fact_datetime
from public.shipping s
inner join status_mart as sm
on  s.shippingid = sm.shippingid
and sm.max_dat = s.state_datetime; 

--view shipping_datamart
create view shipping_datamart as (
select
	si.shippingid,
	vendorid,
	date_part('day',age(shipping_end_fact_datetime,shipping_start_fact_datetime)) as full_day_at_shipping,
	case when shipping_end_fact_datetime > shipping_plan_datetime then 1 else 0end as is_delay,
	case when status = 'finished' then 1 else 0 end as is_shipping_finish,
	case when shipping_end_fact_datetime > shipping_plan_datetime then date_part('day',age(shipping_end_fact_datetime,shipping_plan_datetime)) else 0 end as delay_day_at_shipping,
	payment_amount,
	payment_amount*( shipping_country_base_rate + agreement_rate + shipping_transfer_rate) as vat,
	payment_amount*agreement_commission as profit
from public.shipping_info si 
inner join public.shipping_transfer st 
on si.transfer_type_id = st.id 
inner join public.shipping_country_rates scr 
on si.shipping_country_id  = scr.id 
inner join public.shipping_agreement sa 
on si.agreementid = sa.agreementid 
inner join public.shipping_status ss
on ss.shippingid = si.shippingid)
