//! Multi-repo facade: re-exports the repository sync and git status modules and their
//! most used types under one import.
//!
//! Holds no state and allocates nothing; ownership rules are those of `multirepo/sync.zig`
//! and `multirepo/status.zig`.

pub const sync = @import("multirepo/sync.zig");
pub const status = @import("multirepo/status.zig");

// Re-export commonly used types
pub const SyncOptions = sync.SyncOptions;
pub const RepoStatus = sync.RepoStatus;
pub const GitStatus = status.GitStatus;
