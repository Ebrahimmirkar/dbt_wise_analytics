with actor_reviews as (
    select * , Datefromparts(year(handling_time_end),month(handling_time_end),1) as month_start ,extract(month, handling_time_end) as group_month
    from {{ref("int_reviews_with_metrics")}}
),

actor_cases as (
    select *
    from {{ref("int_cases_with_metrics")}}
),


actor_review_metrics as (
    select 

    actor_id,
    month_start,
    group_month,

    --volume metrics 
    count(review_id) as total_reviews_handled, 
    count(distinct(case_id)) as total_cases_handled, 
    count(distinct(case_id))/count(review_id) as avg_review_per_case,

    --Time performance metrics 
    avg(handling_duration_mins) as avg_handling_duration_mins, 
    median(handling_duration_mins) as median_handling_duration_mins,
    avg(backlog_to_handling_mins) as avg_response_time_mins, 
    median(backlog_to_handling_mins) as median_response_time_mins,

    --- Quality Metrics 
    avg(case when is_any_outlier then 1.0 else 0.0 end) as outlier_rate, 
    count(case when is_any_outlier then 1 else 0 end) as total_outlier_reviews,

    --case type distribution 
    count(distinct case when case_type = 'TYPE_ONE' then 1 end) as type_one_cases,
    count(distinct case when case_type = 'TYPE_TWO' then 1 end ) as type_two_cases, 
    count(distinct case when case_type = 'TYPE_THREE' then 1 end) as type_three_cases,

    -- Speed Categorization
    avg(case 
    when handling_performance = 'Fast' then 1
    when handling_performance = 'Average' then 2
    when handling_performance = 'Slow' then 3 end) as avg_speed_score, 
    --workload distribution
    count(review_id)/30 as avg_reviews_per_day   -- dividing by 30 as granularity is 1 month



    from actor_reviews
    group by actor_id, month_start, group_month
),

actor_case_metrics as (
    select 
    last_reviewing_actor as actor_id, 
    Datefromparts(year(last_handling_date),month(last_handling_date),1) as group_last_month_start,
    extract(month, last_handling_date) as group_last_handling_month,
    count(case_id) as cases_completed, 
    avg(total_lifecycle_mins) as avg_case_lifecycle_mins, 
    avg(total_handling_duration_mins) as avg_handling_duration_mins, 


    --complexity handling
    count(case when case_complexity = 'Simple' then 1 end) as simple_cases_completed, 
    count(case when case_complexity = 'Standard' then 1 end) as standard_cases_completed, 
    count(case when case_complexity = 'Complex' then 1 end) as complex_cases_completed, 
    count(case when case_complexity = 'High Complexity' then 1 end) as highly_complex_cases_completed, 


    from actor_cases
    where last_reviewing_actor is not null
    group by last_reviewing_actor,group_last_month_start, group_last_handling_month
),

combined_actor_data as (

    select 
    arm.actor_id,
    arm.month_start,
    arm.group_month, 

    ---volumes 
    arm.total_reviews_handled,
    arm.total_cases_handled, 
    coalesce(acm.cases_completed, 0) as total_cases_completed, 
    arm.avg_review_per_case,


    ---performance metrics 
    arm.avg_handling_duration_mins,
    arm.median_handling_duration_mins,
    arm.avg_response_time_mins,
    arm.median_response_time_mins,

    ---quality metrics 
    arm.outlier_rate,
    arm.total_outlier_reviews,
    
    --complexity_handling
    arm.type_one_cases/arm.total_cases_handled as type_one_ratio, 
    arm.type_two_cases/arm.total_cases_handled as type_two_ratio, 
    arm.type_three_cases/arm.total_cases_handled as type_three_ratio, 

    coalesce(acm.simple_cases_completed,0) as simple_cases_completed, 
    coalesce(acm.standard_cases_completed,0) as standard_cases_completed,
    coalesce(acm.complex_cases_completed,0) as complex_cases_completed,
    coalesce(acm.highly_complex_cases_completed,0) as highly_complex_cases_completed,

    arm.avg_speed_score


    
    from actor_review_metrics arm
    left join actor_case_metrics acm on acm.actor_id = arm.actor_id and arm.month_start = acm.group_last_month_start and acm.group_last_handling_month = arm.group_month 

)

select * 

from combined_actor_data
order by actor_id, group_month
