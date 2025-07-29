with cleaned_data as (
    select

    --primary identifiers 
    case_id, 
    review_id, 
    customer_id,
    actor_id,
    case_type,

    --casting datetime fields
    try_cast(case_created_time as timestamp) as case_created_time,
    try_cast(case_backlog_entry_time as timestamp) as case_backlog_entry_time,
    try_cast(handling_time_start as timestamp) as handling_time_start,
    try_cast(handling_time_end as timestamp) as handling_time_end,
    



    --decision fields 
    ops_decision,
    final_state

    from {{ref("raw_ops_cases")}}

),


calculated_metrics as (

    select
    *,

    --Time diff calculations (mins)
    datediff('minute',case_created_time, case_backlog_entry_time) as created_to_backlog_mins,
    datediff('minute', case_backlog_entry_time, handling_time_start) as backlog_to_handling_mins,
    datediff('minute', handling_time_start, handling_time_end) as handling_duration_mins,


    --Time diff calculations (hours)

    datediff('minute',case_created_time, case_backlog_entry_time)/60 as created_to_backlog_hours,
    datediff('minute', case_backlog_entry_time, handling_time_start)/60 as backlog_to_handling_hours,
    datediff('minute', handling_time_start, handling_time_end)/60  as handling_duration_hours,


    --Date parts 
    date(handling_time_start) as handling_date,
    extract(year from handling_time_start) as handling_year, 
    extract(month from handling_time_start) as handling_month, 
    extract(week from handling_time_start)  as handling_week, 
    extract(DOW from handling_time_start)  as handling_day_of_week, 
    extract(hour from handling_time_start) as handling_hour, 


    --Data quality flags

    case 
    when case_created_time is null or case_backlog_entry_time is null or handling_time_start is null or handling_time_end is null 
    then True 
    else False end as has_missing_timestamps, 

    case 
    when handling_time_end < handling_time_start or handling_time_start < case_backlog_entry_time or case_backlog_entry_time <case_created_time
    then True 
    else False end as has_invalid_time_sequence,

    case 
    when handling_duration_mins < 0
    then True
    else False end as has_negative_handling_time, 

    case 
    when backlog_to_handling_mins < 0
    then True
    else False end as has_negative_backlog_time


    from cleaned_data

)

select 

*

from calculated_metrics
where not has_missing_timestamps   -- filters out records with missing timestamps 
and not has_invalid_time_sequence  ---filters out records with invalid time sequence