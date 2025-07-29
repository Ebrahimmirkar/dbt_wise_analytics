with source as (

    select *
    from ops_cases

)

select 

case_id, 
review_id, 
customer_id, 
actor_id, 
case_type,
case_created_time, 
case_backlog_entry_time, 
handling_time_start, 
handling_time_end, 
ops_decision, 
final_state

from source