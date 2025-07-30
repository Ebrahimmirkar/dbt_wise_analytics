with review_data as (
    select 
    *
    from {{ref("int_reviews_with_metrics")}}
),


actor_dim as (
    select 
    actor_id, 
    case 
    when count(review_id) >= 1000 then 'High Volume'
    when count(review_id) >= 500 then 'Medium Volume'
    when count(review_id) >= 100 then 'Low Volume'
    else 'Newbie' end as volume_category,

    case
   
    when (count(case when case_type = 'TYPE_THREE' then 1 end)/count(distinct case_id)) >= 0.6 then 'TYPE_THREE Specialist'
    when (count(case when case_type = 'TYPE_TWO' then 1 end)/count(distinct case_id)) >= 0.6 then 'TYPE_TWO Specialist'
    when (count(case when case_type = 'TYPE_ONE' then 1 end)/count(distinct case_id)) >= 0.6 then 'TYPE_ONE Specialist'
    else 'Generalist'
    end as specialization_type,

    avg(handling_duration_hours) as avg_total_handling_duration_hours,
    avg(case WHEN is_any_outlier then 1.0 else 0 end) as actor_outlier_rate, 

  CASE 
    WHEN DATEDIFF(DAY, MIN(handling_time_start), MAX(handling_time_end)) + 1 <= 30 THEN 'Beginner'
    WHEN DATEDIFF(DAY, MIN(handling_time_start), MAX(handling_time_end)) + 1 BETWEEN 31 AND 90 THEN 'Intermediate'
    ELSE 'Experienced'
  END AS tenure_category
    
    from review_data
    group by  actor_id
),

case_context as (
    select 
    case_id, 
    max(case_complexity) as case_complexity, 
    case when count(total_reviews) > 1 then True else False end as is_multi_review_case, 
    MAX(unique_actors_involved) as case_actors_involved

    from {{ref("int_cases_with_metrics")}}
    group by case_id

),

reviews as (
    select 

    --primary identifiers 
    rd.review_id,
    rd.case_id,
    rd.customer_id,
    rd.actor_id,
    rd.case_type,

    --Time dimensions by handling time start 
    
    rd.case_created_time,
    rd.case_backlog_entry_time,
    rd.handling_time_start,
    rd.handling_time_end,
    rd.handling_date,
    rd.handling_year,
    rd.handling_month,
    rd.handling_week,
    rd.handling_day_of_week,
    rd.handling_hour,

    ---Time metrics (in hours - can be converted laters if visualization becomes an issue with too many decimals )
    
    rd.created_to_backlog_hours,
    rd.backlog_to_handling_hours,
    rd.handling_duration_hours,
    

    -- Business fields
    rd.ops_decision,
    rd.final_state,

    --performance metrics 
    rd.handling_performance,
    rd.response_speed_category,
    

    --outlier flags 
    rd.is_outlier_created_to_backlog,
    rd.is_outlier_backlog_to_handle,
    rd.is_outlier_handling_hours,
    

    --case context 
    rd.case_review_rank_desc,
    cc.case_complexity,
    cc.case_actors_involved,
    is_multi_review_case,

    --actor context
    ad.volume_category,
    ad.specialization_type, 
    ad.tenure_category as actor_tenure, 
    ad.avg_total_handling_duration_hours as actor_avg_handling_hours, 
    ad.actor_outlier_rate, 

    --review position context 
    case 
    when case_review_rank_asc = 1 then 'First Review'
    when case_review_rank_desc = 1 then 'Final Review'
    else 'Mid-Review'
    end as review_postition, 

    --handling hours 
    case 
    when rd.handling_hour between 9 and 17 then 'Business Hours'
    when rd.handling_hour between 7 and 19 then 'Extended Hours'
    else 'Off-Hours'
    end as service_hours, 

    case when rd.handling_day_of_week in (6,7) then ('Weekend') else 'Weekday' end as handling_day_type, 

    ---business impact indicators 

    case 
    when rd.handling_duration_hours <= 1 then 'Immediate'
    when rd.handling_duration_hours <= 4 then 'Same Day'
    when rd.handling_duration_hours <=24 then 'Next Day'
    else 'Delayed'
    end as response_timeliness,

    case 
    when rd.is_any_outlier and case_review_rank_desc = 1 then 'final_review_outlier'
    when rd.is_any_outlier then 'review_outlier'
    else 'Normal Review'
    end as quality_flag
    



    from review_data rd 
    left join actor_dim ad on rd.actor_id = ad.actor_id
    left join case_context cc on cc.case_id = rd.case_id



),

final_reviews as (
    select *,
    case 
    when handling_duration_hours <= 0.25 then 'Immediate'
    when handling_duration_hours <= 0.5 then 'Fast'
    when handling_duration_hours <= 1.0 then 'Standard'
    else 'Slow'
    end as handling_speed_detail  


    from reviews



)

select *
from final_reviews