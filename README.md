# bisect_tool
Identify the optimization pass causing the problem with the LLVM based compiler

./bisect_opt.sh '<compiler command>' <source.c> '<expected-output-pattern>'

Example with ICX compiler:
./bisect_opt.sh icx test_mf_conversion_strict.c 'FAIL: Mismatch detected between original and volatile loop!'
It will identify the optimization pass causing the failure.

Example with IFX compiler:
 ./besect2.sh ifx test_fail.f90 SIGSEGV
It will identify the optimization pass causing the Seg Fault.
