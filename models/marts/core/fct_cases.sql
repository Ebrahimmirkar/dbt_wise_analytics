with case_data as (
    select *
    from {{ref("int_cases_with_metrics")}}
),

actor_tenure as (
    select 
    last_reviewing_actor, 
    CASE 
    WHEN DATEDIFF(DAY, MIN(created_time), MAX(created_time))+1 <= 30 THEN 'Beginner'
    WHEN DATEDIFF(DAY, MIN(created_time), MAX(created_time))+1 BETWEEN 31 AND 90 THEN 'Intermediate'
    ELSE 'Experienced'
    END AS tenure_category

    from {{ref("int_cases_with_metrics")}}
    group by last_reviewing_actor

),
actor_dim as (
    select 
    a.last_reviewing_actor, 
    case 
    when sum(a.total_reviews) >= 1000 then 'Heavy Volume'
    when sum(a.total_reviews) >= 500 then 'Moderate Volume'
    when sum(a.total_reviews) >= 100 then 'Light Volume'
    else 'Onboarded' end as volume_category,

    case
   
    when (count(case when case_type = 'TYPE_THREE' then 1 end)/count(distinct case_id)) >= 0.6 then 'TYPE_THREE Specialist'
    when (count(case when case_type = 'TYPE_TWO' then 1 end)/count(distinct case_id)) >= 0.6 then 'TYPE_TWO Specialist'
    when (count(case when case_type = 'TYPE_ONE' then 1 end)/count(distinct case_id)) >= 0.6 then 'TYPE_ONE Specialist'
    else 'Generalist'
    end as specialization_type,

    max(t.tenure_category) as tenure_category
    
    from {{ref('int_cases_with_metrics')}} a
    left join actor_tenure t on t.last_reviewing_actor = a.last_reviewing_actor 
    group by a.last_reviewing_actor

),



fact_cases as (

    select 
    cd.case_id, 
    cd.customer_id, 
    cd.case_type, 
    cd.final_state,

    --Time Dimensions 
    cd.created_time,
    cd.case_backlog_entry_time, 
    cd.first_handling_time_start,
    cd.last_handling_time_end,
    cd.completiondate,
    cd.completion_month,
    cd.completion_week,
    cd.completion_year,


    ---case metrics 
    cd.total_reviews,
    cd.unique_actors_involved,
    cd.total_handling_duration_hours,
    cd.total_lifecycle_hours,
    cd.case_created_to_backlog_hours,
    cd.avg_backlog_to_handle_hours,
    cd.avg_handling_duration_hours,
    

    --quality metrics 
    cd.outlier_reviews_count, 
    cd.outlier_rate,
    cd.avg_handling_speed_score,
    cd.case_complexity, 


    -- case flags
    case when total_reviews > 1 then 1 else 0 end as is_multi_review_case, 
    cd.high_outlier_case, 
    cd.multi_actor_case, 
    cd.high_review_count_case,
    
    --actor info
    cd.last_reviewing_actor, 
    cd.last_ops_decision, 
    ad.volume_category, 
    ad.specialization_type, 
    ad.tenure_category,

    --derived business metrics 
    case
    when cd.total_lifecycle_hours <= 24 then 'Same Day'
    when cd.total_lifecycle_hours <= 72 then 'Within 3 Days'
    when cd.total_lifecycle_hours <= 168 then 'Within 1 week'
    else 'Over 1 Week' end as resolution_speed_category,

    case 
    when cd.avg_backlog_to_handle_hours <= 2 then 'Fast Response'
    when cd.avg_backlog_to_handle_hours <= 4 then 'Standard Response'
    when cd.avg_backlog_to_handle_hours <= 9 then 'Slow Response'
    else 'Unsatisfactory Response'
    end as response_time_category,

    case 
    when cd.case_type = 'TYPE_ONE' and cd.total_lifecycle_hours <= 9 then True
    when cd.case_type = 'TYPE_TWO' and cd.total_lifecycle_hours <= 24 then True
    when cd.case_type = 'TYPE_THREE' and cd.total_lifecycle_hours <= 48 then True
    else False
    end as meets_sla_target,

    -- customer experience indicators higher is better 
    case 
    when cd.total_reviews = 1 and cd.total_lifecycle_hours <= 9 then 10
    when cd.total_reviews <= 2 and cd.total_lifecycle_hours <= 24 then 7
    when cd.total_reviews <= 3 and cd.total_lifecycle_hours <= 48 then 4
    else 1
    end as customer_experience_rating,

-- operational efficiency indicators
    cd.total_handling_duration_hours / nullif(cd.total_lifecycle_hours, 0) as handling_efficiency_ratio,

    case 
    when cd.unique_actors_involved = 1 then 'Single Agent Resolution'
    when cd.unique_actors_involved = 2 then 'Two Agent Handoff'
    else 'Multiple Agent Escalation'
    end as agent_handoff_pattern,





    from case_data cd 
    left join actor_dim ad on ad.last_reviewing_actor = cd.last_reviewing_actor
),
final_fact_cases as (
    select 
        *,
        
        -- business priority scoring (for capacity planning)
        case 
            when case_type = 'TYPE_THREE' and not meets_sla_target then 'Critical'
            when case_type = 'TYPE_TWO' and not meets_sla_target then 'High'
            when case_type = 'TYPE_ONE' and not meets_sla_target then 'Medium'
            else 'Low'
        end as priority_level,
        
        -- risk indicators
        case 
            when high_outlier_case and multi_actor_case then 'High Risk'
            when high_outlier_case or multi_actor_case then 'Medium Risk'
            else 'Low Risk'
        end as operational_risk_level
        
    from fact_cases
)

select * from final_fact_cases



