#!/bin/sh

test_description='Test flux job manager job hold (single mode)'

. `dirname $0`/job-manager/sched-helper.sh

. $(dirname $0)/sharness.sh

test_under_flux 4 job

flux setattr log-stderr-level 1

test_expect_success 'flux-job: generate jobspec for simple test job' '
        flux jobspec srun -n1 hostname >basic.json
'

test_expect_success 'unload job-exec module to prevent job execution' '
        flux module remove job-exec
'

test_expect_success 'job-manager: initially run without scheduler' '
        flux module unload sched-simple
'

test_expect_success 'job-manager: submit 5 jobs (job 2 held)' '
        flux job submit --flags=debug basic.json >job1.id &&
        flux job submit --flags=debug --urgency=0 basic.json >job2.id &&
        flux job submit --flags=debug basic.json >job3.id &&
        flux job submit --flags=debug basic.json >job4.id &&
        flux job submit --flags=debug basic.json >job5.id
'

test_expect_success HAVE_JQ 'job-manager: job state SSSS (no scheduler)' '
        jmgr_check_state $(cat job1.id) S &&
        jmgr_check_state $(cat job2.id) S &&
        jmgr_check_state $(cat job3.id) S &&
        jmgr_check_state $(cat job4.id) S &&
        jmgr_check_state $(cat job5.id) S
'

test_expect_success HAVE_JQ 'job-manager: no annotations (SSSSS)' '
        jmgr_check_no_annotations $(cat job1.id) &&
        jmgr_check_no_annotations $(cat job2.id) &&
        jmgr_check_no_annotations $(cat job3.id) &&
        jmgr_check_no_annotations $(cat job4.id) &&
        jmgr_check_no_annotations $(cat job5.id)
'

# --setbit 0x2 enables creation of reason_pending field
# flux queue stop/start to ensure no raciness with setting up debug bits
test_expect_success 'job-manager: load sched-simple w/ 1 core' '
        flux R encode -r0 -c0 >R.test &&
        flux resource reload R.test &&
        flux queue stop &&
        flux module load sched-simple mode=limited=1 &&
        flux module debug --setbit 0x2 sched-simple &&
        flux queue start
'

test_expect_success HAVE_JQ 'job-manager: job state RSSSS' '
        jmgr_check_state $(cat job1.id) R &&
        jmgr_check_state $(cat job2.id) S &&
        jmgr_check_state $(cat job3.id) S &&
        jmgr_check_state $(cat job4.id) S &&
        jmgr_check_state $(cat job5.id) S
'

test_expect_success HAVE_JQ 'job-manager: annotations job 3 pending, job 2 held (RSSS)' '
        jmgr_check_annotation $(cat job1.id) "sched.resource_summary" "\"rank0/core0\"" &&
        jmgr_check_no_annotations $(cat job2.id) &&
        jmgr_check_annotation $(cat job3.id) "sched.reason_pending" "\"insufficient resources\"" &&
        jmgr_check_no_annotations $(cat job4.id) &&
        jmgr_check_no_annotations $(cat job5.id)
'

test_expect_success 'job-manager: job 4 hold' '
        flux job urgency $(cat job4.id) 0
'

test_expect_success 'job-manager: cancel job 1' '
        flux job cancel $(cat job1.id)
'

test_expect_success HAVE_JQ 'job-manager: job state ISRSS (job 3 run, job 2 held)' '
        jmgr_check_state $(cat job1.id) I &&
        jmgr_check_state $(cat job2.id) S &&
        jmgr_check_state $(cat job3.id) R &&
        jmgr_check_state $(cat job4.id) S &&
        jmgr_check_state $(cat job5.id) S
'

test_expect_success HAVE_JQ 'job-manager: annotations job 5 pending (job 2/4 held)' '
        jmgr_check_no_annotations $(cat job1.id) &&
        jmgr_check_no_annotations $(cat job2.id) &&
        jmgr_check_annotation $(cat job3.id) "sched.resource_summary" "\"rank0/core0\"" &&
        jmgr_check_no_annotations $(cat job4.id) &&
        jmgr_check_annotation $(cat job5.id) "sched.reason_pending" "\"insufficient resources\""
'

test_expect_success 'job-manager: job 4 release (higher urgency)' '
        flux job urgency $(cat job4.id) 20
'

test_expect_success HAVE_JQ 'job-manager: annotations job 4 pending' '
        jmgr_check_no_annotations $(cat job1.id) &&
        jmgr_check_no_annotations $(cat job2.id) &&
        jmgr_check_annotation $(cat job3.id) "sched.resource_summary" "\"rank0/core0\"" &&
        jmgr_check_annotation $(cat job4.id) "sched.reason_pending" "\"insufficient resources\"" &&
        jmgr_check_no_annotations $(cat job5.id)
'

test_expect_success 'job-manager: cancel job 3' '
        flux job cancel $(cat job3.id)
'

test_expect_success HAVE_JQ 'job-manager: job state ISIRS (job 4 run, job 2 held)' '
        jmgr_check_state $(cat job1.id) I &&
        jmgr_check_state $(cat job2.id) S &&
        jmgr_check_state $(cat job3.id) I &&
        jmgr_check_state $(cat job4.id) R &&
        jmgr_check_state $(cat job5.id) S
'

test_expect_success HAVE_JQ 'job-manager: annotations job 5 pending (job 2 held)' '
        jmgr_check_no_annotations $(cat job1.id) &&
        jmgr_check_no_annotations $(cat job2.id) &&
        jmgr_check_no_annotations $(cat job3.id) &&
        jmgr_check_annotation $(cat job4.id) "sched.resource_summary" "\"rank0/core0\"" &&
        jmgr_check_annotation $(cat job5.id) "sched.reason_pending" "\"insufficient resources\""
'

test_expect_success 'job-manager: cancel job 4' '
        flux job cancel $(cat job4.id)
'

test_expect_success HAVE_JQ 'job-manager: job state ISIIR (job 5 run, job 2 held)' '
        jmgr_check_state $(cat job1.id) I &&
        jmgr_check_state $(cat job2.id) S &&
        jmgr_check_state $(cat job3.id) I &&
        jmgr_check_state $(cat job4.id) I &&
        jmgr_check_state $(cat job5.id) R
'

test_expect_success HAVE_JQ 'job-manager: annotations no job pending (job 2 held)' '
        jmgr_check_no_annotations $(cat job1.id) &&
        jmgr_check_no_annotations $(cat job2.id) &&
        jmgr_check_no_annotations $(cat job3.id) &&
        jmgr_check_no_annotations $(cat job4.id) &&
        jmgr_check_annotation $(cat job5.id) "sched.resource_summary" "\"rank0/core0\""
'

test_expect_success 'job-manager: job 2 release' '
        flux job urgency $(cat job2.id) 16
'

test_expect_success HAVE_JQ 'job-manager: annotations job 2 pending' '
        jmgr_check_no_annotations $(cat job1.id) &&
        jmgr_check_annotation $(cat job2.id) "sched.reason_pending" "\"insufficient resources\"" &&
        jmgr_check_no_annotations $(cat job3.id) &&
        jmgr_check_no_annotations $(cat job4.id) &&
        jmgr_check_annotation $(cat job5.id) "sched.resource_summary" "\"rank0/core0\""
'

test_expect_success 'job-manager: cancel remaining jobs' '
        flux job cancel $(cat job2.id) &&
        flux job cancel $(cat job5.id)
'

test_done
