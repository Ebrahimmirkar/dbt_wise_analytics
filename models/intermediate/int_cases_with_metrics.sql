with review_data as (
    select * 
    from {{ref("int_reviews_with_metrics")}}
),


case_aggregations as(
    select
    case_id, 

    --case attributes taken from the latest review 
    max(case when case_review_rank_desc = 1 then customer_id end) as customer_id,
    max(case when case_review_rank_desc = 1 then case_type end) as case_type,
    max(case when case_review_rank_desc = 1 then final_state end) as final_state, 

    --time attributes
    min(case_created_time) as created_time, 
    min(case_backlog_entry_time) as case_backlog_entry_time,

    --first and last handling times 
    min(handling_time_start) as first_handling_time_start,
    max(handling_time_end) as last_handling_time_end, 

    --review and actor count per case
    count(review_id) as total_reviews, 
    count(distinct actor_id) as unique_actors_involved, 

    --initial created to backlog minutes  
    datediff(minute, min(case_created_time),min(case_backlog_entry_time))  as case_created_to_backlog_mins, 
    avg(backlog_to_handling_mins) as avg_backlog_to_handle_mins, 
    avg(handling_duration_mins) as avg_handling_duration_mins, 
    sum(handling_duration_mins) as total_handling_duration_mins, 

    --case lifecycle duration 
    datediff(minutes, min(case_created_time),max(handling_time_end)) as total_lifecycle_mins,

    --outlier_counts
    max(case when is_outlier_created_to_backlog and case_review_rank_asc = 1 then True else False end) as is_case_outlier,
    sum(case when is_any_outlier then 1 else 0 end) as outlier_reviews_count, 
    avg(case when is_any_outlier then 1.0 else 0.0 end) as outlier_rate, 


    --decision patterns 
    count(distinct ops_decision) as unique_decisions_count, 

    --performance metrics 
    avg(case
        when handling_performance = 'Fast' then 1
        when handling_performance = 'Average' then 2 
        when handling_performance = 'Slow' then 3
        end) as avg_handling_speed_score,  -- lower means better

    --identifying the case closing details 
    max(case when case_review_rank_desc = 1 then actor_id end) as last_reviewing_actor, 
    max(case when case_review_rank_desc = 1 then ops_decision end ) as last_ops_decision, 
    max(case when case_review_rank_desc = 1 then handling_time_end end) as last_handling_date


    from review_data    
    group by case_id 

),

final_cases as (

    select
    *,

    case
    when total_reviews = 1 and avg_handling_duration_mins <= 2  then 'Simple'
    when total_reviews <=2 and avg_handling_duration_mins <= 5  then 'Standard'
    when total_reviews <= 4 and avg_handling_duration_mins <= 20  then 'Complex'
    else 'Highly Complex'
    end as case_complexity,

    --performance flags 
    case when outlier_rate > 0.5 then True else False end as high_outlier_case, 
    case when total_reviews > 3 then True else False end as high_review_count_case, 
    case when unique_actors_involved > 2 then True else False end as multi_actor_case, 

    --completiondate flags 
    Date(last_handling_date) as completiondate, 
    extract(year from last_handling_date) as completion_year, 
    extract(month from last_handling_date) as completion_month,
    extract(week from last_handling_date) as completion_week


    from case_aggregations
)

select * from final_cases