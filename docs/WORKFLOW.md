# Workflow Guide

This document describes the intended operator flow for the current MapleStory tooling suite.

## Overview

The practical working sequence is:

1. Prepare an extracted `Base.wz`
2. Generate or load an item catalogue
3. Select and apply item IDs
4. Render a single frame
5. Batch export an action or set of actions
6. Run audit or diff tooling when validating output

## 1. Prepare extracted source data

The tools assume you have an extracted MapleStory `Base.wz` tree available on disk.

At minimum, the character tooling expects the `Character/Character.wz` tree.
For catalogue naming and some metadata-rich flows, `String/String.wz/Eqp.img.xml` is also useful.

## 2. Start from the GUI

Launch the desktop GUI:

```powershell
python character_tooling_gui.py
```

The GUI is the main operator surface and is organized around a left-to-right workflow:
- Start Here
- Catalogue
- Render
- Batch Export
- Diff

## 3. Catalogue stage

Use the Catalogue tab to generate or load item catalogue data.

Typical result:
- `catalogue_all.csv`
- category-specific CSV files
- catalogue summary JSON
- catalogue index markdown

Purpose:
- search by item name or ID
- inspect category mappings
- apply IDs directly into render slots

## 4. Render stage

Use the Render tab to validate a build with a single composed frame before attempting larger exports.

Typical checks:
- does the character compose correctly?
- is the layer order right?
- are there unresolved assets?
- do weapon and hair/cap interactions look correct?

Typical outputs:
- one PNG frame
- optional JSON metadata with draw order, anchors, fallback selections, unresolved entries, and policies

## 5. Batch Export stage

Once a frame is correct, move to Batch Export.

You can use it to:
- export a frame range for one action
- auto-detect a full action timeline
- export all compatible actions
- write per-frame JSON metadata
- generate GIFs
- generate sprite sheets

Typical outputs:
- PNG frame sequence
- optional GIF
- optional sprite sheet
- batch summary JSON

## 6. Validation stage

There are two main post-export validation directions.

### Alignment audit

Run the alignment audit when you want to inspect:
- fallback rates
- jitter and positional stability
- anchor mismatch
- skipped-frame reasons
- unresolved asset behavior

### Tree diff

Run the diff tool when comparing two extracted `Character.wz` trees.

It helps classify changes into:
- structural
- timing
- composition
- compatibility
- art changes via PNG comparison

## 7. Compatibility analysis

Use the weapon compatibility reporting when you need to know which actions are actually supported by a given weapon or weapon family.

This is useful for:
- deciding which actions are safe to export
- understanding why a weapon may disappear on certain actions
- building stricter action filters

## Suggested practical routine

For day-to-day use, the recommended rhythm is:

1. Sync or set `Base.wz`
2. Generate/load catalogue
3. Apply IDs
4. Render one frame
5. Fix any unresolved or visible composition issues
6. Batch export
7. Run audit if output quality matters
8. Run diff only when comparing two source versions

## Failure handling mindset

If something looks wrong:
- verify the item IDs are correct
- render a single frame before running batch export again
- inspect unresolved output in render metadata
- check whether the weapon actually supports the requested action
- run alignment audit on the batch summary if the issue is subtle

## Bottom line

The repo is designed to move from source inspection to composition to export to validation. The fastest way to stay productive is to keep that order and avoid jumping straight to batch export before a single-frame render looks right.
