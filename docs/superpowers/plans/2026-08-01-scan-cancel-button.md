# Scan Cancel Button (#3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or executing-plans.

**Goal:** Cancel button on Smart Scan and Duplicates scanning UI; return to idle cleanly.

**Architecture:** `ScanCoordinator.cancel()` + watch-task cancel for Smart Scan; retained `scanTask` for Duplicates. Post-await cancel check in coordinator.

**Tech Stack:** Swift 6, SwiftUI, XCTest
