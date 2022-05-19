# Проект 2
Опишите здесь поэтапно ход решения задачи. Вы можете ориентироваться на тот план выполнения проекта, который мы предлагаем в инструкции на платформе.

### Создаем справочник стоимости доставки в страны и наполняем данными
```
CREATE TABLE public.shipping_country_rates(
  ID                              SERIAL,
  shipping_country                TEXT,
  shipping_country_base_rate      NUMERIC(14,3),
  PRIMARY KEY (ID));
  
INSERT INTO public.shipping_country_rates (shipping_country,shipping_country_base_rate)
SELECT DISTINCT
	shipping_country,
	shipping_country_base_rate
FROM public.shipping;  
  
 
```

### Создаем справочник тарифов доставки вендора по договору и наполняем данными
```
CREATE TABLE public.shipping_agreement(
  agreementid                    BIGINT,
  agreement_number               TEXT,
  agreement_rate                 NUMERIC(14,3),
  agreement_commission           NUMERIC(14,3),
  PRIMARY KEY (agreementid));
  
INSERT INTO public.shipping_agreement (agreementid,agreement_number,agreement_rate,agreement_commission)
SELECT DISTINCT
	(regexp_split_to_array(vendor_agreement_description, E'\\:+'))[1]::int,
	(regexp_split_to_array(vendor_agreement_description, E'\\:+'))[2]::text,
	(regexp_split_to_array(vendor_agreement_description, E'\\:+'))[3]::numeric,
	(regexp_split_to_array(vendor_agreement_description, E'\\:+'))[4]::numeric
FROM public.shipping;  
```

### Создаем справочник о типах доставки и наполняем данными
```
CREATE TABLE public.shipping_transfer(
  id                            SERIAL,
  transfer_type                 TEXT,
  transfer_model       			    TEXT,
  shipping_transfer_rate        NUMERIC(14,3),
  PRIMARY KEY (id));
  
INSERT INTO public.shipping_transfer (transfer_type,transfer_model,shipping_transfer_rate)
SELECT DISTINCT
	(regexp_split_to_array(shipping_transfer_description, E'\\:+'))[1]::text,
	(regexp_split_to_array(shipping_transfer_description, E'\\:+'))[2]::text,
	shipping_transfer_rate
FROM public.shipping;
```

### Создаем shipping_info с уникальными доставками shippingid и связываем с таблицами выше и наполняем данными
```
  CREATE TABLE public.shipping_info(
  shippingid                  BIGINT,
  vendorid                    BIGINT,
  payment_amount              NUMERIC(14,2) ,
  shipping_plan_datetime      TIMESTAMP,
  transfer_type_id            BIGINT,
  shipping_country_id         BIGINT,
  agreementid                 BIGINT,
  PRIMARY KEY (shippingid),
  FOREIGN KEY (transfer_type_id) REFERENCES public.shipping_transfer(id),
  FOREIGN KEY (shipping_country_id) REFERENCES public.shipping_country_rates(id),
  FOREIGN KEY (agreementid) REFERENCES public.shipping_agreement(agreementid));
  
INSERT INTO public.shipping_info(shippingid,vendorid,payment_amount,shipping_plan_datetime,transfer_type_id,shipping_country_id,agreementid)
SELECT DISTINCT
	  shippingid,
  	vendorid,
  	payment_amount,
  	shipping_plan_datetime,
  	st.id as transfer_type_id,
  	scr.id as shipping_country_id,
  	(regexp_split_to_array(vendor_agreement_description, E'\\:+'))[1]::int as agreementid
FROM public.shipping s
INNER JOIN public.shipping_transfer st 
ON (regexp_split_to_array(shipping_transfer_description, E'\\:+'))[1]::text = st.transfer_type 
AND (regexp_split_to_array(shipping_transfer_description, E'\\:+'))[2]::text = st.transfer_model
INNER JOIN public.shipping_country_rates scr
ON s.shipping_country  = scr.shipping_country;
```

### Создаем таблицу статусов о доставке shipping_status и наполняем данными
```
CREATE TABLE public.shipping_status(
  shippingid                    BIGINT,
  status                        TEXT,
  state                         TEXT,
  shipping_start_fact_datetime  TIMESTAMP,
  shipping_end_fact_datetime    TIMESTAMP,
  PRIMARY KEY (shippingid));
  
WITH status_mart AS (
SELECT
	shippingid,
	max(case when state = 'booked' then state_datetime end)  as shipping_start_fact_datetime,
	max(case when state = 'recieved' then state_datetime end) as shipping_end_fact_datetime,
	max(state_datetime) as max_dat
FROM public.shipping s
WHERE state IN ('recieved', 'booked')
GROUP BY 
  shippingid)


INSERT INTO public.shipping_status
SELECT DISTINCT
	s.shippingid,
	status,
	state,
	shipping_start_fact_datetime,
	shipping_end_fact_datetime
FROM public.shipping s
INNER JOIN status_mart as sm
ON  s.shippingid = sm.shippingid
AND sm.max_dat = s.state_datetime;
```

### Создаем витрину
```
CREATE VIEW shipping_datamart AS (
SELECT
	si.shippingid,
	vendorid,
	date_part('day',age(shipping_end_fact_datetime,shipping_start_fact_datetime)) as full_day_at_shipping,
	case when shipping_end_fact_datetime > shipping_plan_datetime then 1 else 0end as is_delay,
	case when status = 'finished' then 1 else 0 end as is_shipping_finish,
	case when shipping_end_fact_datetime > shipping_plan_datetime then date_part('day',age(shipping_end_fact_datetime,shipping_plan_datetime)) else 0 end as delay_day_at_shipping,
	payment_amount,
	payment_amount*( shipping_country_base_rate + agreement_rate + shipping_transfer_rate) as vat,
	payment_amount*agreement_commission as profit
FROM public.shipping_info si 
INNER JOIN public.shipping_transfer st 
ON si.transfer_type_id = st.id 
INNER JOIN public.shipping_country_rates scr 
ON si.shipping_country_id  = scr.id 
INNER JOIN public.shipping_agreement sa 
ON si.agreementid = sa.agreementid 
INNER JOIN public.shipping_status ss
ON ss.shippingid = si.shippingid)
```
