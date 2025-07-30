with base_reviews as (
    select *
    from {{ref("stg_raw_transformed")}}
),

--calculating percentiles using the IQR method for flagging outliers 

percentiles_calc as (
    select 
    case_type, 

    --created to backlog percentiles ()
    percentile_cont(0.25) within group (order by created_to_backlog_hours) as q1_created_to_backlog,
    percentile_cont(0.75) within group (order by created_to_backlog_hours) as q3_created_to_backlog, 

    --Backlog to handling percentiles
    percentile_cont(0.25) within group (order by backlog_to_handling_hours) as q1_backlog_to_handling,
    percentile_cont(0.75) within group (order by backlog_to_handling_hours) as q3_backlog_to_handling, 

    -- Handling duration to percentiles 
    percentile_cont(0.25) within group (order by handling_duration_hours) as q1_handling_hours, 
    percentile_cont(0.75) within group (order by handling_duration_hours) as q3_handling_hours, 

    from base_reviews 
    where 
    created_to_backlog_hours >=0
    and backlog_to_handling_hours >= 0
    and handling_duration_hours >= 0

    group by case_type

),

flagged_outliers as (

select 
br.*,

--display quartiles 
pc.q1_created_to_backlog,
pc.q3_created_to_backlog,
pc.q1_backlog_to_handling,
pc.q3_backlog_to_handling,
pc.q1_handling_hours,
pc.q3_handling_hours,

--flagging outlier using IQR method 
case
when br.created_to_backlog_hours < (pc.q1_created_to_backlog - 3 * (pc.q3_created_to_backlog - pc.q1_created_to_backlog ))
or br.created_to_backlog_hours > (pc.q3_created_to_backlog + 3 * (pc.q3_created_to_backlog - pc.q1_created_to_backlog ))
then True 
else False 
end as is_outlier_created_to_backlog,

case 
when br.backlog_to_handling_hours < (pc.q1_backlog_to_handling - 3 * (pc.q3_backlog_to_handling - pc.q1_backlog_to_handling))
or br.backlog_to_handling_hours > (pc.q3_backlog_to_handling + 3 * (pc.q3_backlog_to_handling - pc.q1_backlog_to_handling))
then True
else False
end as is_outlier_backlog_to_handle,

case 
when br.handling_duration_hours < (pc.q1_handling_hours - 3 * (pc.q3_handling_hours - pc.q1_handling_hours))
or br.handling_duration_hours > (pc.q3_handling_hours + 3 * (pc.q3_handling_hours - pc.q1_handling_hours))
then True
else False
end as is_outlier_handling_hours,

    --ranking review order
    row_number()over(partition by br.case_id order by br.handling_time_start desc) as case_review_rank_desc,
    --to get the first review for case_metrics
    row_number()over(partition by br.case_id order by br.handling_time_start asc) as case_review_rank_asc

from base_reviews br 
left join percentiles_calc pc on pc.case_type = br.case_type


),

final_reviews as (
    select
    *,
    --combined_outlier_flag
    (is_outlier_backlog_to_handle or is_outlier_handling_hours) as is_any_outlier,

    --performance category
    case
    when handling_duration_hours <= q1_handling_hours then 'Fast'
    when handling_duration_hours <= q3_handling_hours then 'Average'
    else 'Slow'
    end as handling_performance,

    case 
    when backlog_to_handling_hours <= q1_backlog_to_handling then 'Quick Response'
    when backlog_to_handling_hours <= q3_backlog_to_handling then 'Standard Response'
    else 'Delayed Response'
    end as response_speed_category

    from flagged_outliers
)


select * from final_reviews