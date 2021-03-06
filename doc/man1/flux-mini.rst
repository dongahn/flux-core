.. flux-help-include: true

============
flux-mini(1)
============


SYNOPSIS
========

**flux** **mini** **submit** [OPTIONS] [*--ntasks=N*] COMMAND...

**flux** **mini** **bulksubmit** [OPTIONS] [*--ntasks=N*] COMMAND...

**flux** **mini** **run** [OPTIONS] [*--ntasks=N*] COMMAND...

**flux** **mini** **batch** [OPTIONS] *--nslots=N* SCRIPT...

**flux** **mini** **alloc** [OPTIONS] *--nslots=N* [COMMAND...]

DESCRIPTION
===========

flux-mini(1) submits jobs to run under Flux. In the case of **submit**
or **run** the job consists of *N* copies of COMMAND launched together
as a parallel job, while **batch** and **alloc** submit a script or launch
a command as the initial program of a new Flux instance.

If *--ntasks* is unspecified, a value of *N=1* is assumed. Commands that
take *--nslots* have no default and require that *--nslots* be explicitly
specified.

The **submit** and **batch** commands enqueue the job and print its numerical
Job ID on standard output.

The **run** and **alloc** commands do the same interactively, blocking until
the job has completed.

The **bulksubmit** command enqueues one job each for a set of inputs read
on either stdin, or given on the command line. The inputs are optionally
substituted in ``COMMAND`` and/or many submission options. See more in the
:ref:`bulksubmit` section below.

For **flux-mini batch**, the SCRIPT given on the command line is assumed
to be a file name, unless the *--wrap* option used, and the script
file is read and submitted along with the job. If no SCRIPT is
provided, then one will be read from *stdin*.

**flux-mini alloc** works similarly to **batch**, but instead blocks until
the job has started and interactively attaches to the new Flux instance.
By default, a new shell is spawned as the initial program of the instance,
but this may be overridden by supplying COMMAND on the command line.

The intent is for the "mini" commands to remain simple with stable interfaces
over time, making them suitable for use in scripts. For advanced usage,
see flux-run(1) and flux-submit(1).

The available OPTIONS are detailed below.


JOB PARAMETERS
==============

These commands accept only the simplest parameters for expressing
the size of the parallel program and the geometry of its task slots:

The **run** and **submit** commands take the following options to specify
the size of the job request:

**-n, --ntasks=N**
   Set the number of tasks to launch (default 1).

**-c, --cores-per-task=N**
   Set the number of cores to assign to each task (default 1).

**-g, --gpus-per-task=N**
   Set the number of GPU devices to assign to each task (default none).

The **batch** and **alloc** commands do not launch tasks directly, and
therefore job parameters are specified in terms of resource slot size
and number of slots. A resource slot can be thought of as the minimal
resources required for a virtual task. The default slot size is 1 core.

**-n, --nslots=N**
   Set the number of slots requested. This parameter is required.

**-c, --cores-per-slot=N**
   Set the number of cores to assign to each slot (default 1).

**-g, --gpus-per-slot=N**
   Set the number of GPU devices to assign to each slot (default none).

The **run**, **submit**, **batch**, and **alloc** commands also take
following additional job parameters:

**-N, --nodes=N**
   Set the number of nodes to assign to the job. Tasks will be distributed
   evenly across the allocated nodes. It is an error to request more nodes
   than there are tasks. If unspecified, the number of nodes will be chosen
   by the scheduler.

**-t, --time-limit=FSD**
   Set a time limit for the job in Flux standard duration (RFC 23).
   FSD is a floating point number with a single character units suffix
   ("s", "m", "h", or "d"). If unspecified, the job is subject to the
   system default time limit.


STANDARD I/O
============

By default, task stdout and stderr streams are redirected to the
KVS, where they may be accessed with the ``flux job attach`` command.

In addition, ``flux-mini run`` processes standard I/O in real time,
emitting the job's I/O to its stdout and stderr.

**--output=TEMPLATE**
   Specify the filename *TEMPLATE* for stdout redirection, bypassing
   the KVS.  *TEMPLATE* may be a mustache template which supports the
   tags *{{id}}* and *{{jobid}}* which expand to the current jobid
   in the F58 encoding.  If needed, an alternate encoding can be
   selected by using a subkey with the name of the desired encoding,
   e.g. *{{id.dec}}*. Supported encodings include *f58* (the default),
   *dec*, *hex*, *dothex*, and *words*. For **flux mini batch** the
   default *TEMPLATE* is *flux-{{id}}.out*. To force output to KVS so it is
   available with ``flux job attach``, set *TEMPLATE* to *none* or *kvs*.

**--error=TEMPLATE**
   Redirect stderr to the specified filename *TEMPLATE*, bypassing the KVS.
   *TEMPLATE* is expanded as described above.

**-l, --label-io**
   Add task rank prefixes to each line of output.

ENVIRONMENT
===========

By default, ``flux-mini`` duplicates the current environment when
submitting jobs. However, a set of environment manipulation options are
provided to give fine control over the requested environment submitted
with the job.

**--env=RULE**
   Control how environment variables are exported with *RULE*. See
   *ENV RULE SYNTAX* section below for more information. Rules are
   applied in the order in which they are used on the command line.
   This option may be specified multiple times.

**--env-remove=PATTERN**
   Remove all environment variables matching *PATTERN* from the current
   generated environment. If *PATTERN* starts with a ``/`` character,
   then it is considered a regex(7), otherwise *PATTERN* is treated
   as a shell glob(7). This option is equivalent to ``--env=-PATTERN``
   and may be used multiple times.

**--env-file=FILE**
   Read a set of environment *RULES* from a *FILE*. This option is
   equivalent to ``--env=^FILE`` and may be used multiple times.

ENV RULES
=========

The ``--env*`` options of ``flux-mini`` allow control of the environment
exported to jobs via a set of *RULE* expressions. The currently supported
rules are

 * If a rule begins with ``-``, then the rest of the rule is a pattern
   which removes matching environment variables. If the pattern starts
   with ``/``, it is a regex(7), optionally ending with ``/``, otherwise
   the pattern is considered a shell glob(7) expression.

   Examples:
      ``-*`` or ``-/.*/`` filter all environment variables creating an
      empty environment.

 * If a rule begins with ``^`` then the rest of the rule is a filename
   from which to read more rules, one per line. The ``~`` character is
   expanded to the user's home directory.

   Examples:
      ``~/envfile`` reads rules from file ``$HOME/envfile``

 * If a rule is of the form ``VAR=VAL``, the variable ``VAR`` is set
   to ``VAL``. Before being set, however, ``VAL`` will undergo simple
   variable substitution using the Python ``string.Template`` class. This
   simple substitution supports the following syntax:

     * ``$$`` is an escape; it is replaced with ``$``
     * ``$var`` will substitute ``var`` from the current environment,
       falling back to the process environment. An error will be thrown
       if environment variable ``var`` is not set.
     * ``${var}`` is equivalent to ``$var``
     * Advanced parameter substitution is not allowed, e.g. ``${var:-foo}``
       will raise an error.

   Examples:
       ``PATH=/bin``, ``PATH=$PATH:/bin``, ``FOO=${BAR}something``

 * Otherwise, the rule is considered a pattern from which to match
   variables from the process environment if they do not exist in
   the generated environment. E.g. ``PATH`` will export ``PATH`` from the
   current environment (if it has not already been set in the generated
   environment), and ``OMP*`` would copy all environment variables that
   start with ``OMP`` and are not already set in the generated environment.
   It is important to note that if the pattern does not match any variables,
   then the rule is a no-op, i.e. an error is *not* generated.

   Examples:
       ``PATH``, ``FLUX_*_PATH``, ``/^OMP.*/``

Since ``flux-mini`` always starts with a copy of the current environment,
the default implicit rule is ``*`` (or ``--env=*``). To start with an
empty environment instead, the ``-*`` rule or ``--env-remove=*`` option
should be used. For example, the following will only export the current
``PATH`` to a job:

::

    flux mini run --env-remove=* --env=PATH ...


Since variables can be expanded from the currently built environment, and
``--env`` options are applied in the order they are used, variables can
be composed on the command line by multiple invocations of ``--env``, e.g.:

::

    flux mini run --env-remove=* \
                  --env=PATH=/bin --env='PATH=$PATH:/usr/bin' ...

Note that care must be taken to quote arguments so that ``$PATH`` is not
expanded by the shell.


This works particularly well when specifying rules in a file:

::

    -*
    OMP*
    FOO=bar
    BAR=${FOO}/baz

The above file would first clear the environment, then copy all variables
starting with ``OMP`` from the current environment, set ``FOO=bar``,
and then set ``BAR=bar/baz``.


EXIT STATUS
===========

The job exit status, normally the largest task exit status, is stored
in the KVS. If one or more tasks are terminated with a signal,
the job exit status is 128+signo.

The ``flux-job attach`` command exits with the job exit status.

In addition, ``flux-mini run`` runs until the job completes and exits
with the job exit status.


OTHER OPTIONS
=============

**--urgency=N**
   Specify job urgency, which affects queue order. Numerically higher urgency
   jobs are considered by the scheduler first. Guests may submit jobs with
   urgency in the range of 0 to 16, while instance owners may submit jobs
   with urgency in the range of 0 to 31 (default 16).

**-v, --verbose**
   *(run,alloc,submit,bulksubmit)* Increase verbosity on stderr. For example,
   currently ``flux mini run -v`` displays jobid, ``-vv`` displays job events,
   and ``-vvv`` displays exec events. ``flux mini alloc -v`` forces the command
   to print the submitted jobid on stderr.
   The specific output may change in the future.

**-o, --setopt=KEY[=VAL]**
   Set shell option. Keys may include periods to denote hierarchy.
   VAL is optional and may be valid JSON (bare values, objects, or arrays),
   otherwise VAL is interpreted as a string. If VAL is not set, then the
   default value is 1. See SHELL OPTIONS below.

**--setattr=KEY=VAL**
   Set jobspec attribute. Keys may include periods to denote hierarchy.
   VAL may be valid JSON (bare values, objects, or arrays), otherwise VAL
   is interpreted as a string.

**--dry-run**
   Don't actually submit job. Just emit jobspec on stdout and exit for
   ``run``, ``submit``, ``alloc``, and ``batch``. For ``bulksubmit``,
   emit a line of output including relevant options for each job which
   would have been submitted,

**--debug**
   Enable job debug events, primarily for debugging Flux itself.
   The specific effects of this option may change in the future.

**-B, --broker-opts=OPT**
   *(batch only)* For batch jobs, pass specified options to the Flux brokers
   of the new instance. This option may be specified multiple times.

**--wrap**
   *(batch only)* The ``--wrap`` option wraps the specified COMMAND and ARGS in
   a shell script, by prefixing with ``#!/bin/sh``. If no COMMAND is present,
   then a SCRIPT is read on stdin and wrapped in a /bin/sh script.

**--cc=IDSET**
   *(submit,bulksubmit)* Replicate the job for each ``id`` in ``IDSET``.
   ``FLUX_JOB_CC=id`` will be set in the environment of each submitted job
   to allow the job to alter its execution based on the submission index.
   (e.g. for reading from a different input file).

**--bcc=IDSET**
   *(submit,bulksubmit)* Identical to ``--cc``, but do not set
   ``FLUX_JOB_CC`` in each job. All jobs will be identical copies.

**--wait**
   *(submit,bulksubmit)* Wait on completion of all jobs before exiting.

**--watch**
   *(submit,bulksubmit)* Display output from all jobs. Implies ``--wait``.

**--progress**
   *(submit,bulksubmit)* With ``--wait``, display a progress bar showing
   the progress of job completion. Without ``--wait``, the progress bar
   will show progress of job submission.

**--jps**
   *(submit,bulksubmit)* With ``--progress``, display throughput statistics
   (jobs/s) in the progress bar.

**--define=NAME=CODE**
   *(bulksubmit)* Define a named method that will be made available as an
   attribute during command and option replacement. The string being
   processed is available as ``x``. For example::

   $ seq 1 8 | flux mini bulksubmit --define=pow="2**int(x)" -n {.pow} ...

**--shuffle**
   *(bulksubmit)* Shuffle the list of commands before submission.

**--sep=STRING**
   *(bulksubmit)* Change the separator for file input. The default is
   to separate files (including stdin) by newline. To separate by
   consecutive whitespace, specify ``--sep=none``.

.. _bulksubmit:

BULKSUBMIT
==========

The ``bulksubmit`` utility allows rapid bulk submission of jobs using
an interface similar to GNU parallel or ``xargs``. The command takes
inputs on stdin or the command line (separated by ``:::``), and submits
the supplied command template and options as one job per input combination.

The replacement is done using Python's ``string.format()``, which is
supplied a list of inputs on each iteration. Therefore, in the common case
of a single input list, ``{}`` will work as the substitution string, e.g.::

    $ seq 1 4 | flux mini bulksubmit echo {}
    flux-mini: submit echo 1
    flux-mini: submit echo 2
    flux-mini: submit echo 3
    flux-mini: submit echo 4

With ``--dry-run`` ``bulksubmit`` will print the args and command which
would have been submitted, but will not perform any job submission.

The ``bulksubmit`` command can also take input lists on the command line.
The inputs are separated from each other and the command  with the special
delimiter ``:::``::

    $ flux mini bulksubmit echo {} ::: 1 2 3 4
    flux-mini: submit echo 1
    flux-mini: submit echo 2
    flux-mini: submit echo 3
    flux-mini: submit echo 4

Multiple inputs are combined, in which case each input is passed as a
positional parameter to the underlying ``format()``, so should be accessed
by index::

    $ flux mini bulksubmit --dry-run echo {1} {0} ::: 1 2 ::: 3 4
    flux-mini: submit echo 3 1
    flux-mini: submit echo 4 1
    flux-mini: submit echo 3 2
    flux-mini: submit echo 4 2

If the generation of all combinations of an  input list with other inputs is not
desired, the special input delimited ``:::+`` may be used to "link" the input,
so that only one argument from this source will be used per other input,
e.g.::

    $ flux mini bulksubmit --dry-run echo {0} {1} ::: 1 2 :::+ 3 4
    flux-mini: submit 1 3
    flux-mini: submit 2 4

The linked input will be cycled through if it is shorter than other inputs.

An input list can be read from a file with ``::::``::

    $ seq 0 3 >inputs
    $ flux mini bulksubmit --dry-run :::: inputs
    flux-mini: submit 0
    flux-mini: submit 1
    flux-mini: submit 2
    flux-mini: submit 3

If the filename is ``-`` then ``stdin`` will be used. This is useful
for including ``stdin`` when reading other inputs.

The delimiter ``::::+`` indicates that the next file is to be linked to
the inputs instead of combined with them, as with ``:::+``.

There are several predefined attributes for input substitution.
These include:

 - ``{.%}`` returns the input string with any extension removed.
 - ``{./}`` returns the basename of the input string.
 - ``{./%}`` returns the basename of the input string with any
   extension removed.
 - ``{.//}`` returns the dirname of the input string
 - ``{seq}`` returns the input sequence number (0 origin).

Note that besides ``{seq}``, these attributes can also take the input
index, e.g. ``{0.%}`` or ``{1.//}``, when multiple inputs are used.

Additional attributes may be defined with the ``--define`` option, e.g.::

    $ flux mini bulksubmit --dry-run --define=p2='2**int(x)' -n {.p2} hostname \
       ::: $(seq 0 4)
    flux-mini: submit -n1 hostname
    flux-mini: submit -n2 hostname
    flux-mini: submit -n4 hostname
    flux-mini: submit -n8 hostname
    flux-mini: submit -n16 hostname

The input string being indexed is passed to defined attributes via the
local ``x`` as seen above.

SHELL OPTIONS
=============

These options are provided by built-in shell plugins that may be
overridden in some cases:

**mpi=spectrum**
   Load the MPI personality plugin for IBM Spectrum MPI. All other MPI
   plugins are loaded by default.

**cpu-affinity=per-task**
   Tasks are distributed across the assigned resources.

**cpu-affinity=off**
   Disable task affinity plugin.

**gpu-affinity=per-task**
   GPU devices are distributed evenly among local tasks. Otherwise,
   GPU device affinity is to the job.

**gpu-affinity=off**
   Disable GPU affinity for this job.

**verbose**
   Increase verbosity of the job shell log.

**pmi.kvs=native**
   Use the native Flux KVS instead of the PMI plugin's built-in key exchange
   algorithm.

**pmi.exchange.k=N**
   Configure the PMI plugin's built-in key exchange algorithm to use a
   virtual tree fanout of ``N`` for key gather/broadcast.  The default is 2.


RESOURCES
=========

Github: http://github.com/flux-framework
