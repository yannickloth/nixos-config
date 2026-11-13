# The systemd user slice shared by the local inference stacks
# (packages/strata/home.nix and packages/unsloth-studio/{home,container}.nix).
#
# Why a slice: without one, every unit sits in the user manager's app.slice
# beside the browser, the IDE and syncthing - CPUWeight 100, MemoryHigh
# infinity, no distinction between a chat turn and a 15-thread expert pool.
# Measured on laptop-p16 (2026-11-05): CPU pressure "some" 50%, GPU at 100%,
# 450 MiB of VRAM free, and Strata, Firefox and the terminal all in the same
# cgroup with the same weight.
#
# Weights, not quotas, on purpose. CPUWeight decides only who wins while both
# sides want the CPU, so an engine keeps nearly the whole machine when the
# desktop is idle. A CPUQuota would cost throughput all the time. 20 against
# the desktop's 100 means a saturating engine gets about one sixth of the CPU
# while a person is using the machine.
#
# MemoryHigh is a soft ceiling: above it the kernel reclaims inside this
# slice first, instead of taking page cache from the browser. 64 GiB holds
# Strata's ~40 GiB expert arena plus its pinned KV cache and request buffers
# (unit peak 44.7 GB on 2026-11-05) with room to spare. It is a guard against
# a runaway allocation, not a budget the model has to fit into.
#
# The services join this slice with `Slice = "ai.slice"` and keep their own
# `Nice = 10`, which orders their threads against each other inside the share.
#
# Owned by the package modules (packages/strata/home.nix and
# packages/unsloth-studio/home.nix import this file), not by one user's config:
# whichever of the two runs, on whichever host, must get the same budget. The
# definition is conditional so a host that enables neither gets no empty unit.
{ config, lib, ... }:
{
  config = lib.mkIf
    ((config.strata.enable or false) || (config.unsloth-studio.enable or false))
    {
      systemd.user.slices.ai = {
        Unit = {
          Description = "Local AI inference (yields CPU and memory to the desktop session)";
        };
        Slice = {
          CPUWeight = 20; # app.slice and session.slice run at 100
          IOWeight = 20;
          MemoryHigh = "64G";
        };
      };
    };
}
