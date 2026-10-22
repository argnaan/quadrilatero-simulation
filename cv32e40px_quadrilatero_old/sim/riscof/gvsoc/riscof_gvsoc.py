import os
import shlex
import shutil
import sys
import logging

import riscof.utils as utils
from riscof.pluginTemplate import pluginTemplate

logger = logging.getLogger()


class gvsoc(pluginTemplate):
    """RISCOF DUT plugin for the GVSOC CV32E40P instruction set simulator.

    Runs each test on a cv32e40p-v2-standalone* target and rebuilds the
    signature from the run log (see sig_extract.py). Text and data addresses
    match the RTL and SAIL plugins, so signatures are directly comparable.
    """

    __model__ = "gvsoc"
    __version__ = "1.0.0"

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)

        config = kwargs.get('config')
        if config is None:
            logger.error("Config node for gvsoc missing.")
            raise SystemExit(1)

        self.pluginpath = os.path.abspath(config['pluginpath'])
        self.isa_spec = os.path.abspath(config['ispec'])
        self.platform_spec = os.path.abspath(config['pspec'])

        self.num_jobs = str(config['jobs'] if 'jobs' in config else 1)
        self.target_run = not ('target_run' in config and config['target_run'] == '0')

        self.sw_toolchain_prefix = str(config.get('sw_toolchain_prefix', 'unknown'))
        self.gvsoc_target = str(config.get('target', 'cv32e40p-v2-standalone-fpu'))
        self.sim_timeout = str(config.get('sim_timeout', '600'))
        # Logged because a typo in the key name degrades to the default
        # silently, and the wrong target still produces a plausible run.
        for key in ('target', 'sim_timeout', 'env_bin'):
            if key not in config:
                logger.warning("gvsoc plugin: '%s' not in config, using default",
                               key)
        logger.info("gvsoc plugin: target=%s sim_timeout=%ss",
                    self.gvsoc_target, self.sim_timeout)

        self.gvrun = config.get('gvrun')
        if self.gvrun is None:
            logger.error("gvsoc plugin: 'gvrun' not set in config.ini.")
            raise SystemExit(1)
        self.gvrun = os.path.abspath(self.gvrun)
        if not os.path.isfile(self.gvrun):
            logger.error("gvsoc plugin: gvrun not found at " + self.gvrun)
            raise SystemExit(1)

        # gvrun is a shell wrapper that resolves python3 from PATH, so the
        # GVSOC python environment has to be on it. Resolved here and baked
        # into the make recipes: the recipes must not contain a '$', make
        # would expand it before the shell sees it.
        env_bin = config.get('env_bin')
        path = os.environ.get('PATH', '')
        if env_bin:
            path = os.path.abspath(env_bin) + os.pathsep + path
        self.run_env = 'env PATH=' + shlex.quote(path)

        # Same interpreter that runs RISCOF: sig_extract.py needs pyelftools,
        # which is a RISCOF dependency.
        self.python_exe = sys.executable

    def initialise(self, suite, work_dir, archtest_env):
        self.work_dir = work_dir
        self.suite_dir = suite

        self.compile_cmd = 'riscv{1}-{2}-elf-gcc -march={0} \
          -static -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles \
          -T ' + self.pluginpath + '/env/link.ld\
          -I ' + self.pluginpath + '/env/\
          -I ' + archtest_env + ' {3} -o {4} {5}'

    def build(self, isa_yaml, platform_yaml):
        ispec = utils.load_yaml(isa_yaml)['hart0']

        self.xlen = ('64' if 64 in ispec['supported_xlen'] else '32')

        self.isa = 'rv' + self.xlen
        if "I" in ispec["ISA"]:
            self.isa += 'i'
        if "M" in ispec["ISA"]:
            self.isa += 'm'
        if "F" in ispec["ISA"]:
            self.isa += 'f'
        if "D" in ispec["ISA"]:
            self.isa += 'd'
        if "C" in ispec["ISA"]:
            self.isa += 'c'
        if "Zicsr" in ispec["ISA"]:
            self.isa += '_zicsr'
        if "Zifencei" in ispec["ISA"]:
            self.isa += '_zifencei'

        self.compile_cmd = self.compile_cmd + ' -mabi=' + \
            ('lp64 ' if 64 in ispec['supported_xlen'] else 'ilp32 ')

        compiler = "riscv{0}-{1}-elf-gcc".format(self.xlen, self.sw_toolchain_prefix)
        if shutil.which(compiler) is None:
            logger.error(compiler + ": executable not found. Please check environment setup.")
            raise SystemExit(1)

    def runTests(self, testList, cgf_file=None):
        makefile = os.path.join(self.work_dir, "Makefile." + self.name[:-1])
        if os.path.exists(makefile):
            os.remove(makefile)
        make = utils.makeUtil(makefilePath=makefile)
        make.makeCommand = 'make -k -j' + self.num_jobs

        for testname in testList:
            testentry = testList[testname]
            test = testentry['test_path']
            test_dir = testentry['work_dir']
            test_name = test.rsplit('/', 1)[1][:-2]

            elf = '{0}.elf'.format(test_name)
            sig_file = os.path.join(test_dir, self.name[:-1] + ".signature")
            log_file = '{0}.gvsoc.log'.format(test_name)

            compile_macros = ' -D' + " -D".join(testentry['macros'])
            test_compile_cmd = self.compile_cmd.format(
                self.isa, self.xlen, self.sw_toolchain_prefix, test, elf, compile_macros)

            objdmp_cmd = 'riscv{0}-{1}-elf-objdump -D -M no-aliases -S {2} > {3}.disass'.format(
                self.xlen, self.sw_toolchain_prefix, elf, test_name)

            # The exit device logs each signature store on its debug trace;
            # sig_extract.py turns those lines back into the signature.
            # '- || true': a non-zero exit (timeout, model abort) must still
            # reach the extractor, which records how far the run got.
            sim_cmd = ('{0} timeout {1} {2} --target={3} --work-dir={4}/gvsoc_work '
                       '--parameter binary={4}/{5} run --trace=/soc/exit '
                       '--trace-level=debug > {6} 2>&1 || true').format(
                self.run_env, self.sim_timeout, shlex.quote(self.gvrun),
                self.gvsoc_target, test_dir, elf, log_file)

            extract_cmd = '{0} {1}/sig_extract.py {2} {3} {4}'.format(
                shlex.quote(self.python_exe), self.pluginpath, log_file, elf, sig_file)

            execute = '@cd {0}; {1}; {2}; {3}; {4}'.format(
                test_dir, test_compile_cmd, objdmp_cmd, sim_cmd, extract_cmd)

            make.add_target(execute, tname=test_name)

        self.timeout = 20000

        if self.target_run:
            make.execute_all(self.work_dir, self.timeout)
        else:
            print("No target to Run")
