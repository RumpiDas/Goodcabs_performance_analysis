### 1.City-Level Fare and Trip Summary Report ###
WITH CTE as(
SELECT
       c.city_name,
       count(t.trip_id) as total_trips,
       round(SUM(t.fare_amount)/SUM(t.distance_travelled_km), 2) as avg_fare_per_km
FROM fact_trips as t
JOIN dim_city as c
ON c.city_id = t.city_id
GROUP BY c.city_name
)
SELECT 
    *,
    ROUND((total_trips * 100 / SUM(total_trips) OVER()), 2) AS percentage_contribution
FROM CTE;


### 2.Monthly City-Level Trips Target Performance Report ### 
WITH CTE as (
SELECT 
     c.city_id,
     c.city_name,
     d.month_name,
     d.start_of_month,
     count(ft.trip_id) as actual_trips,
     target.total_target_trips as target_trips
 FROM trips_db.fact_trips as ft
 JOIN dim_city as c ON c.city_id = ft.city_id
 JOIN dim_date as d ON d.date = ft.date
 JOIN targets_db.monthly_target_trips as target
 ON d.start_of_month = target.month and c.city_id = target.city_id
 GROUP BY c.city_id, d.month_name, d.start_of_month,target.total_target_trips
 )
SELECT city_name,
   month_name,
   actual_trips,
   target_trips,
 case 
   when actual_trips > target_trips then "Above Target"
   when actual_trips < target_trips then "Below Target"
   end as performance_status,
 ROUND(
 case
       WHEN target_trips = 0 THEN 0
       ELSE (actual_trips - target_trips) * 100.0 / target_trips
     END, 2) as percentage_difference
FROM CTE;

### 3.City-Level Repeat Passenger Trip Frequency Report ###
WITH Distribution as (
SELECT
        c.city_name,
        rtd.trip_count,
        SUM(rtd.repeat_passenger_count) AS total_repeat_passengers
    FROM dim_repeat_trip_distribution as rtd
    JOIN dim_city as c on c.city_id=rtd.city_id   
    GROUP BY c.city_name, rtd.trip_count),
TotalPassengersByCity AS (
SELECT
	city_name,
	SUM(total_repeat_passengers) AS total_city_passengers
FROM Distribution
GROUP BY city_name),
PercentageDistribution AS (
    SELECT
        d.city_name,
        d.trip_count,
        ROUND((d.total_repeat_passengers * 100.0) / t.total_city_passengers,2) AS percentage
    FROM
        Distribution d
    JOIN
        TotalPassengersByCity t ON d.city_name = t.city_name
)
SELECT
    city_name,
    MAX(CASE WHEN trip_count = 2 THEN percentage END) AS "2-Trips",
    MAX(CASE WHEN trip_count = 3 THEN percentage END) AS "3-Trips",
    MAX(CASE WHEN trip_count = 4 THEN percentage END) AS "4-Trips",
    MAX(CASE WHEN trip_count = 5 THEN percentage END) AS "5-Trips",
    MAX(CASE WHEN trip_count = 6 THEN percentage END) AS "6-Trips",
    MAX(CASE WHEN trip_count = 7 THEN percentage END) AS "7-Trips",
    MAX(CASE WHEN trip_count = 8 THEN percentage END) AS "8-Trips",
    MAX(CASE WHEN trip_count = 9 THEN percentage END) AS "9-Trips",
    MAX(CASE WHEN trip_count = 10 THEN percentage END) AS "10-Trips"
FROM
    PercentageDistribution
GROUP BY
    city_name
ORDER BY
    city_name;
    
### 4.Identify Cities with Highest and Lowest Total New Passengers ###
WITH CTE1 AS (
SELECT 
   c.city_name,
   sum(ps.new_passengers) as total_new_passengers
FROM trips_db.fact_passenger_summary as ps
JOIN dim_city as c ON c.city_id = ps.city_id
GROUP BY c.city_name),
CTE2 AS (
SELECT 
    city_name,
    total_new_passengers,
    RANK() OVER (ORDER BY total_new_passengers DESC) AS rank_desc,
    RANK() OVER (ORDER BY total_new_passengers ASC) AS rank_asc
FROM CTE1)
SELECT 
    city_name,
    total_new_passengers,
    CASE 
        WHEN rank_desc <= 3 THEN 'Top 3'
        WHEN rank_asc <= 3 THEN 'Bottom 3'
        ELSE NULL
    END AS city_category
FROM CTE2
WHERE rank_desc <= 3 or rank_asc <= 3; 

### 5.Identify Month with Highest Revenue for Each City ###
WITH RevPerMonth AS (
  SELECT 
    c.city_name,
    d.month_name,
    sum(fare_amount) as revenue
  FROM fact_trips as ft
  JOIN dim_date as d ON d.date = ft.date
  JOIN dim_city as c ON c.city_id = ft.city_id
  GROUP BY c.city_name, d.month_name),
MaxRev AS (
  SELECT 
    city_name,
	month_name,
    revenue,
    MAX(revenue) OVER(PARTITION BY city_name) AS max_revenue
  FROM RevPerMonth),
RevPerCity AS (
  SELECT
	 city_name,
     SUM(revenue) as cities_total_rev
   FROM RevPerMonth
   GROUP BY city_name
)
SELECT 
     mr.city_name,
     mr.month_name as highest_revenue_month,
     mr.revenue,
     ROUND((mr.revenue*100)/rpc.cities_total_rev,2) as percentage_contribution
FROM MaxRev as mr
JOIN RevPerCity as rpc ON mr.city_name = rpc.city_name
WHERE mr.revenue = mr.max_revenue
ORDER BY mr.city_name;

## 6.Repeat Passenger Rate Analysis ##
WITH MonthlyRepeatPassengers AS (
SELECT
     c.city_name,
	 d.month_name,
     SUM(ps.total_passengers) as total_passengers,
     SUM(ps.repeat_passengers) as repeat_passengers
 FROM fact_passenger_summary as ps
 JOIN dim_city as c ON c.city_id = ps.city_id
 JOIN dim_date as d ON d.start_of_month = ps.month
 GROUP BY c.city_name,d.month_name),
CityRepeatPassengers AS ( 
SELECT city_name,
       SUM(repeat_passengers) as city_repeat_passengers
FROM MonthlyRepeatPassengers
GROUP BY city_name      
 )
SELECT
	 mrp.city_name,
	 mrp.month_name,
     mrp.total_passengers,
     mrp.repeat_passengers,
    ROUND((mrp.repeat_passengers / mrp.total_passengers)*100, 2) as monthly_repeat_passengers_rate,
    ROUND((mrp.repeat_passengers / crp.city_repeat_passengers) * 100, 2) as city_repeat_passengers_rate
FROM MonthlyRepeatPassengers as mrp 
JOIN CityRepeatPassengers as crp on crp.city_name = mrp.city_name
ORDER BY city_name;