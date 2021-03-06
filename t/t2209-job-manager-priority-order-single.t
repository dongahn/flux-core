#!/bin/sh

test_description='Test flux job manager urgency change to job (mode=single)'

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

test_expect_success 'job-manager: submit 4 jobs' '
        flux job submit --flags=debug basic.json >job1.id &&
        flux job submit --flags=debug basic.json >job2.id &&
        flux job submit --flags=debug basic.json >job3.id &&
        flux job submit --flags=debug basic.json >job4.id
'

test_expect_success HAVE_JQ 'job-manager: job state SSSS (no scheduler)' '
        jmgr_check_state $(cat job1.id) S &&
        jmgr_check_state $(cat job2.id) S &&
        jmgr_check_state $(cat job3.id) S &&
        jmgr_check_state $(cat job4.id) S
'

test_expect_success HAVE_JQ 'job-manager: no annotations (SSSS)' '
        jmgr_check_no_annotations $(cat job1.id) &&
        jmgr_check_no_annotations $(cat job2.id) &&
        jmgr_check_no_annotations $(cat job3.id) &&
        jmgr_check_no_annotations $(cat job4.id)
'

# --setbit 0x2 enables creation of reason_pending field
# flux queue stop/start to ensure no raciness with setting up debug bits
test_expect_success 'job-manager: load sched-simple w/ 2 cores' '
        flux R encode -r0 -c0-1 >R.test &&
        flux resource reload R.test &&
        flux queue stop &&
        flux module load sched-simple mode=limited=1 &&
        flux module debug --setbit 0x2 sched-simple &&
        flux queue start
'

test_expect_success HAVE_JQ 'job-manager: job state RRSS' '
        jmgr_check_state $(cat job1.id) R &&
        jmgr_check_state $(cat job2.id) R &&
        jmgr_check_state $(cat job3.id) S &&
        jmgr_check_state $(cat job4.id) S
'

test_expect_success HAVE_JQ 'job-manager: annotate job id 3 (RRSS)' '
        jmgr_check_annotation $(cat job1.id) "sched.resource_summary" "\"rank0/core0\"" &&
        jmgr_check_annotation $(cat job2.id) "sched.resource_summary" "\"rank0/core1\"" &&
        jmgr_check_annotation $(cat job3.id) "sched.reason_pending" "\"insufficient resources\"" &&
        jmgr_check_no_annotations $(cat job4.id)
'

test_expect_success HAVE_JQ 'job-manager: user annotate jobs' '
        flux job annotate $(cat job3.id) mykey foo &&
        flux job annotate $(cat job4.id) mykey bar
'

test_expect_success HAVE_JQ 'job-manager: annotations in job id 3-4 (RRSS)' '
        jmgr_check_annotation $(cat job1.id) "sched.resource_summary" "\"rank0/core0\"" &&
        jmgr_check_annotation $(cat job2.id) "sched.resource_summary" "\"rank0/core1\"" &&
        jmgr_check_annotation $(cat job3.id) "user.mykey" "\"foo\"" &&
        jmgr_check_annotation $(cat job3.id) "sched.reason_pending" "\"insufficient resources\"" &&
        jmgr_check_annotation $(cat job4.id) "user.mykey" "\"bar\""
'

test_expect_success 'job-manager: increase urgency of job 4' '
        flux job urgency $(cat job4.id) 20
'

test_expect_success HAVE_JQ 'job-manager: annotations in job id 3-4 updated (RRSS)' '
        jmgr_check_annotation $(cat job1.id) "sched.resource_summary" "\"rank0/core0\"" &&
        jmgr_check_annotation $(cat job2.id) "sched.resource_summary" "\"rank0/core1\"" &&
        jmgr_check_annotation $(cat job3.id) "user.mykey" "\"foo\"" &&
        test_must_fail jmgr_check_annotation_exists $(cat job3.id) "sched.reason_pending" &&
        jmgr_check_annotation $(cat job4.id) "user.mykey" "\"bar\"" &&
        jmgr_check_annotation $(cat job4.id) "sched.reason_pending" "\"insufficient resources\""
'

test_expect_success 'job-manager: cancel 2' '
        flux job cancel $(cat job2.id)
'

test_expect_success HAVE_JQ 'job-manager: job state RISR (job 4 runs instead of 3)' '
        jmgr_check_state $(cat job1.id) R &&
        jmgr_check_state $(cat job2.id) I &&
        jmgr_check_state $(cat job3.id) S &&
        jmgr_check_state $(cat job4.id) R
'

test_expect_success HAVE_JQ 'job-manager: annotations in job id 3-4 updated (RISR)' '
        jmgr_check_annotation $(cat job1.id) "sched.resource_summary" "\"rank0/core0\"" &&
        jmgr_check_no_annotations $(cat job2.id) &&
        jmgr_check_annotation $(cat job3.id) "user.mykey" "\"foo\"" &&
        jmgr_check_annotation $(cat job3.id) "sched.reason_pending" "\"insufficient resources\"" &&
        jmgr_check_annotation $(cat job4.id) "sched.resource_summary" "\"rank0/core1\"" &&
        jmgr_check_annotation $(cat job4.id) "user.mykey" "\"bar\"" &&
        test_must_fail jmgr_check_annotation_exists $(cat job4.id) "sched.reason_pending"
'

test_expect_success 'job-manager: submit high urgency job' '
        flux job submit --flags=debug --urgency=20 basic.json >job5.id
'

test_expect_success HAVE_JQ 'job-manager: job state RISRS' '
        jmgr_check_state $(cat job1.id) R &&
        jmgr_check_state $(cat job2.id) I &&
        jmgr_check_state $(cat job3.id) S &&
        jmgr_check_state $(cat job4.id) R &&
        jmgr_check_state $(cat job5.id) S
'

test_expect_success HAVE_JQ 'job-manager: annotations in job id 3-5 updated (RISRS)' '
        jmgr_check_annotation $(cat job1.id) "sched.resource_summary" "\"rank0/core0\"" &&
        jmgr_check_no_annotations $(cat job2.id) &&
        jmgr_check_annotation $(cat job3.id) "user.mykey" "\"foo\"" &&
        test_must_fail jmgr_check_annotation_exists $(cat job3.id) "sched.reason_pending" &&
        jmgr_check_annotation $(cat job4.id) "sched.resource_summary" "\"rank0/core1\"" &&
        jmgr_check_annotation $(cat job4.id) "user.mykey" "\"bar\"" &&
        jmgr_check_annotation $(cat job5.id) "sched.reason_pending" "\"insufficient resources\""
'

PLUGINPATH=${FLUX_BUILD_DIR}/t/job-manager/plugins/.libs
test_expect_success 'job-manager: load priority-invert plugin' '
        flux jobtap load ${PLUGINPATH}/priority-invert.so
'

test_expect_success HAVE_JQ 'job-manager: job state RISRS' '
        jmgr_check_state $(cat job1.id) R &&
        jmgr_check_state $(cat job2.id) I &&
        jmgr_check_state $(cat job3.id) S &&
        jmgr_check_state $(cat job4.id) R &&
        jmgr_check_state $(cat job5.id) S
'

test_expect_success HAVE_JQ 'job-manager: annotations in job id 3-5 updated (RISRS)' '
        jmgr_check_annotation $(cat job1.id) "sched.resource_summary" "\"rank0/core0\"" &&
        jmgr_check_no_annotations $(cat job2.id) &&
        jmgr_check_annotation $(cat job3.id) "sched.reason_pending" "\"insufficient resources\"" &&
        jmgr_check_annotation $(cat job3.id) "user.mykey" "\"foo\"" &&
        jmgr_check_annotation $(cat job4.id) "sched.resource_summary" "\"rank0/core1\"" &&
        jmgr_check_annotation $(cat job4.id) "user.mykey" "\"bar\"" &&
        jmgr_check_no_annotations $(cat job5.id)
'

test_expect_success 'job-manager: cancel 1' '
        flux job cancel $(cat job1.id)
'

test_expect_success HAVE_JQ 'job-manager: job state IISRR (job 5 runs instead of 3)' '
        jmgr_check_state $(cat job1.id) I &&
        jmgr_check_state $(cat job2.id) I &&
        jmgr_check_state $(cat job3.id) R &&
        jmgr_check_state $(cat job4.id) R &&
        jmgr_check_state $(cat job5.id) S
'

test_expect_success HAVE_JQ 'job-manager: annotations in job id 3-5 updated (IISRR)' '
        jmgr_check_no_annotations $(cat job1.id) &&
        jmgr_check_no_annotations $(cat job2.id) &&
        jmgr_check_annotation $(cat job3.id) "sched.resource_summary" "\"rank0/core0\"" &&
        jmgr_check_annotation $(cat job3.id) "user.mykey" "\"foo\"" &&
        jmgr_check_annotation $(cat job4.id) "sched.resource_summary" "\"rank0/core1\"" &&
        jmgr_check_annotation $(cat job4.id) "user.mykey" "\"bar\"" &&
        jmgr_check_annotation $(cat job5.id) "sched.reason_pending" "\"insufficient resources\""
'

test_expect_success 'job-manager: cancel all jobs' '
        flux job cancel $(cat job5.id) &&
        flux job cancel $(cat job4.id) &&
        flux job cancel $(cat job3.id)
'

test_done
