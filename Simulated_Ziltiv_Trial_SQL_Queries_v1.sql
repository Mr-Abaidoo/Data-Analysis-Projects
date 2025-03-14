-----------------------------------------------------------------------------------
-- About this project
-----------------------------------------------------------------------------------

-- This project presents SQL queries designed to analyze clinical trial data based on the RESCUE Study (ClinicalTrials.gov ID: NCT03926117)
-- The study investigated IL-6 inhibition with Ziltivekimab for patients with cardiovascular risk and elevated inflammation markers.
-- The dataset was simulated to reflect key trial parameters
-- The SQL queries in this repository demonstrate data processing, analysis, and reporting skills
-- It covers joins, aggregations, window functions and case statements

-----------------------------------------------------------------------------------
-- #1 Count participants by treatment group
-----------------------------------------------------------------------------------
select
	treatment_group as Treatment_Group,
	count(*) as Total_Participants
from
	ClinicalTrial..ZiltivBaseline	
group by
	treatment_group;

-----------------------------------------------------------------------------------
-- #2 Determine age at enrollment
-----------------------------------------------------------------------------------

--Add a new column
alter 
	table ClinicalTrial..ZiltivBaseline
add 
	Age decimal(3,0)

--Calculate age
update 
	ClinicalTrial..ZiltivBaseline
set
	Age = datediff(year, dob, enrollment_date);

-----------------------------------------------------------------------------------
-- #3 Demographics
-----------------------------------------------------------------------------------

--Age distribution by treatment group and sex
select
	sex as Sex,                --Comment out to view results by treatment group only
	treatment_group as Treatment_Group,
	count(*) as Count,
	cast(round(avg(Age), 1) as decimal(10,1)) as Average_Age,
	min(Age) as Min_Age,
	max(Age) as Max_Age
from
	ClinicalTrial..ZiltivBaseline
group by
	treatment_group, 
	sex;      --Comment out to view results by treatment group only

--Age categorization 
select
	treatment_group,
	case
		when Age between 18 and 40 then '18–40'
		when Age between 41 and 50 then '41–50'
		when Age between 51 and 60 then '51–60'
		when Age between 61 and 70 then '61–70'
		when Age >= 71 then '71+'
		else 'Unknown'
	end as Age_Band,
	count(*) as Count,
	cast(count(*) * 100 / sum(count(*)) over (partition by treatment_group) as decimal(5,1)) as Pct
from
  ClinicalTrial..ZiltivBaseline
group by
    treatment_group,
	case
		when Age between 18 and 40 then '18–40'
		when Age between 41 and 50 then '41–50'
		when Age between 51 and 60 then '51–60'
		when Age between 61 and 70 then '61–70'
		when Age >= 71 then '71+'
		else 'Unknown'
	end
order by
  treatment_group,
  Age_Band;

--Race distribution by treatment group
select
	treatment_group,
	race,
	count(*) as Count
from
	ClinicalTrial..ZiltivBaseline
group by
	treatment_group, 
	race
order by
	treatment_group;

-----------------------------------------------------------------------------------
-- #4 Completion status
-----------------------------------------------------------------------------------

-- Percent completion by sex and treatment group
select
	base.sex AS Sex,
	wk32.treatment_group as Treatment_Group,
	cast(round(
		sum(case when wk32.completion_status = 'Completed' then 1 else 0 end) * 100.0 / count(*), 
		1
	) as decimal(5,1)) as Percent_Completion
from
	ClinicalTrial..ZiltivWeek32 wk32
	JOIN ClinicalTrial..ZiltivBaseline base
	on wk32.participant_id = base.participant_id
group by
	wk32.treatment_group, base.sex
order by
	Treatment_Group, Sex;

--Percent completion by treatment group (Approach 1)
select
	treatment_group as Treatment_Group,
	completion_status as Completion_Status,
	cast(round(count(*) * 100 / sum(count(*)) over (partition by treatment_group), 1) as decimal(5,1)) as Percent_Completion
from
	ClinicalTrial..ZiltivWeek32 wk32
group by
	treatment_group, completion_status
order by
	2;

--Percent completion by treatment group (Approach 2)
select
	treatment_group as Treatment_Group,
	cast(round(
		sum(case when wk32.completion_status = 'Completed' then 1 else 0 end) * 100.0 / count(*), 
		1
	) as decimal(5,1)) as Percent_Completion
from
	ClinicalTrial..ZiltivWeek32 wk32
group by
	treatment_group
order by
	2;

--Percent completion by location
select
	site_name as Location,
	cast(round(
		sum(case when completion_status = 'Completed' then 1 else 0 end) * 100 / count(*), 
		1
	) as decimal(5,1)) as Pct_Completion
from
	ClinicalTrial..ZiltivWeek32
group by
	site_name;

-----------------------------------------------------------------------------------
-- #5 Reason for not completing the study
-----------------------------------------------------------------------------------

--First, verify data consistency in "completion_status" with "reason_notcomplete"
select
  completion_status,
  reason_notcomplete,
  count(*) as Count
from
  ClinicalTrial..ZiltivWeek32
group by
  completion_status, reason_notcomplete
--having
	--completion_status = 'Not Completed'            --Remove comment verify update
order by
  completion_status, reason_notcomplete;

--Assign "N/A" to "reason_nocomplete" column where "completion_status" = "Completed"
update
	ClinicalTrial..ZiltivWeek32
set reason_notcomplete = 
	case
		when completion_status = 'Completed' then 'N/A'
		else reason_notcomplete
	end;

--Reason for not completing study by treatment
select
	treatment_group,
	reason_notcomplete,
	count(*) as Count
from
	ClinicalTrial..ZiltivWeek32
group by
	treatment_group, 
	reason_notcomplete
having
	reason_notcomplete != 'N/A'
order by
	1;

-----------------------------------------------------------------------------------
-- #6 Percent change in hsCRP, Fibrinogen and SAA
-----------------------------------------------------------------------------------

select
	base.treatment_group,
	cast(round(avg((wk13.wk13_hsCRP - base.baseline_hsCRP) / base.baseline_hsCRP * 100), 1) as decimal(5,1)) as Avg_hsCRP_PctChange,
	cast(round(avg((wk13.wk13_fibrinogen - base.baseline_fibrinogen) / base.baseline_fibrinogen * 100), 1) as decimal(5,1)) as Avg_Fibrinogen_PctChange,
	cast(round(avg((wk13.wk13_SAA - base.baseline_SAA) / base.baseline_SAA * 100), 1) as decimal(5,1)) as Avg_SAA_PctChange
from ClinicalTrial..ZiltivBaseline base
	join ClinicalTrial..ZiltivWeek13 wk13
	on base.participant_id = wk13.participant_id
group by
	base.treatment_group;

-----------------------------------------------------------------------------------
-- #6 Effect of treatments on ECG
-----------------------------------------------------------------------------------

-- Individual effect (Positive, Negative or No Change)
select
	base.treatment_group,
	base.baseline_ECG,
	wk32.wk32_ECG,
	case
      -- Positive Effect: Abnormal (clinically significant/not significant) → Normal
      when (base.baseline_ECG LIKE 'Abnormal%' AND wk32.wk32_ECG = 'Normal') 
           OR (base.baseline_ECG = 'Abnormal, clinically significant' AND wk32.wk32_ECG = 'Abnormal, not clinically significant')
      then 'Positive'
      
      -- Negative Effect: Normal → Abnormal (clinically significant/not significant)
      when (base.baseline_ECG = 'Normal' AND wk32.wk32_ECG LIKE 'Abnormal%')
           OR (base.baseline_ECG = 'Abnormal, not clinically significant' AND wk32.wk32_ECG = 'Abnormal, clinically significant')
      then 'Negative'
      
      -- Neutral Effect: No change
      when base.baseline_ECG = wk32.wk32_ECG
      then 'No Change'
      
      -- Default: Other changes (e.g., Indeterminate, Non evaluable, Unknown)
      else 'Other'
    end as ECG_Effect
from ClinicalTrial..ZiltivBaseline base
	join ClinicalTrial..ZiltivWeek32 wk32
	on base.participant_id = wk32.participant_id;

-- Effect (Positive, Negative or No Change) by treatment
with ECG_Outcome as (
  select
    base.treatment_group,
    base.baseline_ECG,
    wk32.wk32_ECG,
    case
      -- Positive Effect: Abnormal (clinically significant/not significant) → Normal
      when (base.baseline_ECG LIKE 'Abnormal%' AND wk32.wk32_ECG = 'Normal') 
           OR (base.baseline_ECG = 'Abnormal, clinically significant' AND wk32.wk32_ECG = 'Abnormal, not clinically significant')
      then 'Positive'
      
      -- Negative Effect: Normal → Abnormal (clinically significant/not significant)
      when (base.baseline_ECG = 'Normal' AND wk32.wk32_ECG LIKE 'Abnormal%')
           OR (base.baseline_ECG = 'Abnormal, not clinically significant' AND wk32.wk32_ECG = 'Abnormal, clinically significant')
      then 'Negative'
      
      -- Neutral Effect: No change
      when base.baseline_ECG = wk32.wk32_ECG
      then 'No Change'
      
      -- Default: Other changes (e.g., Indeterminate, Non evaluable, Unknown)
      else 'Other'
    end as ECG_Effect
  from
    ClinicalTrial..ZiltivBaseline base
    join ClinicalTrial..ZiltivWeek32 wk32
    on base.participant_id = wk32.participant_id
)
select
  treatment_group as Treatment_Group,
  ECG_Effect,
  count(*) AS Count,
  cast(count(*) * 100.0 / sum(count(*)) over (partition by treatment_group) as decimal(5,1)) as Pct
from
  ECG_Outcome
group by
  treatment_group, ECG_Effect
order by
  treatment_group, ECG_Effect;

-----------------------------------------------------------------------------------
-- #6 Impact of treatments on blood pressure
-----------------------------------------------------------------------------------

select
	base.treatment_group,
	cast(round(avg((wk32.wk32_SBP - base.baseline_SBP) / base.baseline_SBP *100), 1) as decimal(5,1)) as Avg_SBP_PctChange,
	cast(round(avg((wk32.wk32_DBP - base.baseline_DBP) / base.baseline_DBP *100), 1) as decimal(5,1)) as Avg_DBP_PctChange
from ClinicalTrial..ZiltivBaseline base
	join ClinicalTrial..ZiltivWeek32 wk32
	on base.participant_id = wk32.participant_id
group by
	base.treatment_group

-----------------------------------------------------------------------------------
-- #7 Adverse Events
-----------------------------------------------------------------------------------

--Number of adverse event types by treatment
select
	treatment_group,
	AE_type,
	count(*) as AE_Count
from 
	ClinicalTrial..ZiltivAdverseEvents
group by
	AE_type, treatment_group
having 
	AE_type != 'None';

--Number of severe adverse event types by treatment
select
	treatment_group,
	SAE_type,
	count(*) as SAE_Count
from 
	ClinicalTrial..ZiltivAdverseEvents
group by
	SAE_type, treatment_group
having 
	SAE_type != 'None';