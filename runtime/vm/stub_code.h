// Copyright (c) 2011, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#ifndef RUNTIME_VM_STUB_CODE_H_
#define RUNTIME_VM_STUB_CODE_H_

#include "vm/allocation.h"
#include "vm/compiler/assembler/assembler.h"
#include "vm/compiler/runtime_api.h"
#include "vm/compiler/stub_code_compiler.h"
#include "vm/object.h"
#include "vm/stub_code_list.h"

namespace dart {

// Forward declarations.
class Code;
class Isolate;
class ObjectPointerVisitor;
class RawCode;
class SnapshotReader;
class SnapshotWriter;

// Is it permitted for the stubs above to refer to Object::null(), which is
// allocated in the VM isolate and shared across all isolates.
// However, in cases where a simple GC-safe placeholder is needed on the stack,
// using Smi 0 instead of Object::null() is slightly more efficient, since a Smi
// does not require relocation.

// class StubCode is used to maintain the lifecycle of stubs.
class StubCode : public AllStatic {
 public:
  // Generate all stubs which are shared across all isolates, this is done
  // only once and the stub code resides in the vm_isolate heap.
  static void Init();

  static void Cleanup();

  // Returns true if stub code has been initialized.
  static bool HasBeenInitialized();

  // Check if specified pc is in the dart invocation stub used for
  // transitioning into dart code.
  static bool InInvocationStub(uword pc, bool is_interpreted_frame);

  // Check if the specified pc is in the jump to frame stub.
  static bool InJumpToFrameStub(uword pc);

  // Returns NULL if no stub found.
  static const char* NameOfStub(uword entry_point);

// Define the shared stub code accessors.
#define STUB_CODE_ACCESSOR(name)                                               \
  static const Code& name() { return *entries_[k##name##Index]; }              \
  static intptr_t name##Size() { return name().Size(); }
  VM_STUB_CODE_LIST(STUB_CODE_ACCESSOR);
#undef STUB_CODE_ACCESSOR

  static RawCode* GetAllocationStubForClass(const Class& cls);

#if !defined(TARGET_ARCH_IA32)
  static RawCode* GetBuildMethodExtractorStub(
      compiler::ObjectPoolBuilder* pool);
#endif

  // Generate the stub and finalize the generated code into the stub
  // code executable area.
  static RawCode* Generate(
      const char* name,
      compiler::ObjectPoolBuilder* object_pool_builder,
      void (*GenerateStub)(compiler::Assembler* assembler));

  static const Code& UnoptimizedStaticCallEntry(intptr_t num_args_tested);

  static const intptr_t kNoInstantiator = 0;
  static const intptr_t kInstantiationSizeInWords = 3;

  static const Code& EntryAt(intptr_t index) { return *entries_[index]; }
  static void EntryAtPut(intptr_t index, Code* entry) {
    ASSERT(entry->IsReadOnlyHandle());
    ASSERT(entries_[index] == nullptr);
    entries_[index] = entry;
  }
  static intptr_t NumEntries() { return kNumStubEntries; }

#if !defined(DART_PRECOMPILED_RUNTIME)
#define GENERATE_STUB(name)                                                    \
  static RawCode* BuildIsolateSpecific##name##Stub(                            \
      compiler::ObjectPoolBuilder* opw) {                                      \
    return StubCode::Generate(                                                 \
        "_iso_stub_" #name, opw,                                               \
        compiler::StubCodeCompiler::Generate##name##Stub);                     \
  }
  VM_STUB_CODE_LIST(GENERATE_STUB);
#undef GENERATE_STUB
#endif  // !defined(DART_PRECOMPILED_RUNTIME)

 private:
  friend class MegamorphicCacheTable;

  enum {
#define STUB_CODE_ENTRY(name) k##name##Index,
    VM_STUB_CODE_LIST(STUB_CODE_ENTRY)
#undef STUB_CODE_ENTRY
        kNumStubEntries
  };

  static Code* entries_[kNumStubEntries];
};

}  // namespace dart

#endif  // RUNTIME_VM_STUB_CODE_H_
