#include <stdio.h>

#include <llvm-c/Analysis.h>
#include <llvm-c/Core.h>
#include <llvm-c/Target.h>
#include <llvm-c/TargetMachine.h>

int main(int argc, char* argv[]) {
  LLVMInitializeNativeTarget();
  LLVMInitializeNativeAsmPrinter();
  char* triple = LLVMGetDefaultTargetTriple();
  char* error;
  LLVMTargetRef target_ref;
  if (LLVMGetTargetFromTriple(triple, &target_ref, &error)) {
      printf("Error: %s\n", error);
      return 1;
  }
  LLVMTargetMachineRef tm_ref = LLVMCreateTargetMachine(
    target_ref,
    triple,
    "",
    "",
    LLVMCodeGenLevelDefault,
    LLVMRelocStatic,
    LLVMCodeModelJITDefault);
  LLVMDisposeMessage(triple);

  LLVMContextRef context = LLVMContextCreate();
  LLVMModuleRef module = LLVMModuleCreateWithNameInContext("module_name", context);
  // LLVMModuleRef module = LLVMModuleCreateWithName("module_name");

  LLVMTypeRef i32type = LLVMIntTypeInContext(context, 32);
  LLVMTypeRef param_types[] = {i32type, i32type};
  LLVMTypeRef func_type = LLVMFunctionType(i32type, param_types, 2, 0);

  LLVMValueRef func = LLVMAddFunction(module, "function_name", func_type);
  LLVMBasicBlockRef entry = LLVMAppendBasicBlockInContext(context, func, "entry");

  LLVMBuilderRef builder = LLVMCreateBuilderInContext(context);
  LLVMPositionBuilderAtEnd(builder, entry);
  LLVMValueRef tmp =
    LLVMBuildAdd(builder, LLVMGetParam(func, 0), LLVMGetParam(func, 1), "add");
  LLVMBuildRet(builder, tmp);

  LLVMDumpModule(module);

  LLVMVerifyModule(module, LLVMAbortProcessAction, &error);
  LLVMDisposeMessage(error);
  return 0;
}
