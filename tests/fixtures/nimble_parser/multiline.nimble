# multiline.nimble — documented miss: multi-line continuation form.
# Only the FIRST quoted package on the `requires` line is captured.
# `second` and `third` on continuation lines are silently dropped.
# Users whose real nimble files use this form must supplement via
# -d:tripwireAuditFFIExtraRequires.
version = "0.1.0"
author = "tripwire-test"
description = "multiline fixture"
license = "MIT"

requires "first >= 1.0",
         "second >= 2.0",
         "third"
