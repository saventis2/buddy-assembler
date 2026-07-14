#!/usr/bin/env python3
"""Desktop GUI for MapleStory character renderer + diff tooling."""

from __future__ import annotations

import argparse
import json
import csv
import random
import threading
import traceback
from pathlib import Path
from typing import Optional

import tkinter as tk
from tkinter import filedialog, messagebox, ttk

from PIL import Image, ImageTk

from diff_character_assets import diff_character_trees
from render_character_frame import render
from build_item_catalogue import build_catalogue as build_character_catalogue
from build_itemwz_catalogue import build_catalogue as build_itemwz_catalogue
from alignment_audit import run_alignment_audit
from character_tooling_core import (
    CLASS_PRESET_DEFS,
    coerce_bool,
    detect_actions,
    detect_action_timeline,
    detect_actions_for_loadout,
    format_count_map,
    get_body_id_pools,
    infer_slot_from_catalogue_categories,
    int_or_none,
    load_eqp_name_index,
    load_weapon_meta_index,
    normalize_catalogue_rows,
    pick_weapon_for_class,
    resolve_catalogue_icon_path,
    validate_base_wz,
)
from character_tooling_ops import (
    resolve_batch_character_out_dir,
    run_batch_export,
)
from wz_shared import (
    ANALYSIS_DIR_ENV_VAR,
    BASE_WZ_ENV_VAR,
    FALLBACK_ANALYSIS_DIR,
    FALLBACK_BASE_WZ,
    resolve_default_path,
    utc_now_iso,
)


# Path override mechanism (precedence: CLI arg > env var > hardcoded default)
# lives in wz_shared.resolve_default_path and is documented once in
# Character-Tooling.md rather than repeated per script.
DEFAULT_BASE_WZ = resolve_default_path(None, BASE_WZ_ENV_VAR, FALLBACK_BASE_WZ)
DEFAULT_ANALYSIS_DIR = resolve_default_path(None, ANALYSIS_DIR_ENV_VAR, FALLBACK_ANALYSIS_DIR)
CATALOGUE_MODE_CHARACTER = "Character (Equip)"
CATALOGUE_MODE_ITEMWZ = "Item.wz (Other Items)"


class App(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title("MapleStory Character Tooling")
        self.geometry("1200x860")
        self.minsize(1000, 760)

        self.image_preview: Optional[ImageTk.PhotoImage] = None
        self.catalogue_build_preview_image: Optional[ImageTk.PhotoImage] = None
        self.catalogue_item_icon_image: Optional[ImageTk.PhotoImage] = None
        self.global_preview_image: Optional[ImageTk.PhotoImage] = None
        self.global_preview_path: Optional[Path] = None
        self._cat_tree_row_lookup: dict[str, dict] = {}
        self._eqp_name_cache_path: Optional[str] = None
        self._eqp_name_index: dict[int, dict] = {}
        self._weapon_meta_cache_path: Optional[str] = None
        self._weapon_meta_index: dict[int, dict] = {}
        self._live_preview_after_id: Optional[str] = None
        self._live_preview_running = False
        self._live_preview_pending = False
        self._live_preview_token = 0

        self._build_ui()

    def _build_ui(self) -> None:
        root_split = ttk.Panedwindow(self, orient="horizontal")
        root_split.pack(fill="both", expand=True, padx=10, pady=10)

        main_area = ttk.Frame(root_split)
        preview_dock = ttk.LabelFrame(root_split, text="Current Character Preview (Persistent)")
        root_split.add(main_area, weight=5)
        root_split.add(preview_dock, weight=2)

        self.notebook = ttk.Notebook(main_area)
        self.notebook.pack(fill="both", expand=True)

        self.guide_tab = ttk.Frame(self.notebook)
        self.catalogue_tab = ttk.Frame(self.notebook)
        self.render_tab = ttk.Frame(self.notebook)
        self.batch_tab = ttk.Frame(self.notebook)
        self.diff_tab = ttk.Frame(self.notebook)

        self.notebook.add(self.guide_tab, text="1) Start Here")
        self.notebook.add(self.catalogue_tab, text="2) Catalogue")
        self.notebook.add(self.render_tab, text="3) Render")
        self.notebook.add(self.batch_tab, text="4) Batch Export")
        self.notebook.add(self.diff_tab, text="5) Diff")

        self._build_guide_tab()
        self._build_catalogue_tab()
        self._build_render_tab()
        self._build_batch_tab()
        self._build_diff_tab()
        self.notebook.select(self.guide_tab)

        self.global_preview_status = tk.StringVar(
            value="Preview updates from Catalogue, Render, and Batch Export."
        )
        ttk.Label(preview_dock, textvariable=self.global_preview_status, wraplength=300).pack(
            anchor="w", padx=8, pady=(8, 6)
        )
        self.global_preview_label = ttk.Label(preview_dock, text="No preview yet.")
        self.global_preview_label.pack(fill="both", expand=True, padx=8, pady=(0, 8))

    def _set_active_tab(self, tab_name: str) -> None:
        tab_map = {
            "guide": self.guide_tab,
            "catalogue": self.catalogue_tab,
            "render": self.render_tab,
            "batch": self.batch_tab,
            "diff": self.diff_tab,
        }
        tab = tab_map.get(tab_name)
        if tab is not None:
            self.notebook.select(tab)

    def on_sync_base_wz_paths(self) -> None:
        source = self.guide_base_wz.get().strip()
        if not source:
            source = DEFAULT_BASE_WZ
        for var_name in ("cat_base_wz", "render_base_wz", "batch_base_wz", "diff_old", "diff_new"):
            var = getattr(self, var_name, None)
            if var is not None:
                var.set(source)
        self.guide_status.set(f"Synced Base.wz across tabs: {source}")

    def _build_guide_tab(self) -> None:
        top = ttk.Frame(self.guide_tab)
        top.pack(fill="x", padx=8, pady=8)

        ttk.Label(
            top,
            text=(
                "Use this workflow left-to-right: Catalogue -> Render -> Batch Export -> Diff (optional)."
            ),
        ).grid(row=0, column=0, columnspan=3, sticky="w", padx=4, pady=(2, 8))

        self.guide_base_wz = tk.StringVar(value=DEFAULT_BASE_WZ)
        self.guide_status = tk.StringVar(value="Set Base.wz once, then sync it to every tab.")
        self._build_labeled_entry(top, 1, "Base.wz path for all tabs", self.guide_base_wz, width=90)
        ttk.Button(top, text="Browse", command=lambda: self._browse_dir(self.guide_base_wz)).grid(
            row=1, column=2, padx=4, pady=4
        )

        nav = ttk.Frame(top)
        nav.grid(row=2, column=0, columnspan=3, sticky="w", padx=4, pady=8)
        ttk.Button(nav, text="Sync Base.wz To All Tabs", command=self.on_sync_base_wz_paths).pack(
            side="left", padx=(0, 8)
        )
        ttk.Button(nav, text="Go To Catalogue", command=lambda: self._set_active_tab("catalogue")).pack(
            side="left", padx=(0, 8)
        )
        ttk.Button(nav, text="Go To Render", command=lambda: self._set_active_tab("render")).pack(
            side="left", padx=(0, 8)
        )
        ttk.Button(nav, text="Go To Batch Export", command=lambda: self._set_active_tab("batch")).pack(
            side="left", padx=(0, 8)
        )
        ttk.Button(nav, text="Go To Diff", command=lambda: self._set_active_tab("diff")).pack(side="left")

        ttk.Label(top, textvariable=self.guide_status).grid(
            row=3, column=0, columnspan=3, sticky="w", padx=4, pady=(0, 6)
        )

        body = ttk.Frame(self.guide_tab)
        body.pack(fill="both", expand=True, padx=8, pady=(0, 8))

        guide_text = tk.Text(body, wrap="word", height=26)
        guide_text.pack(fill="both", expand=True)
        guide_text.insert(
            "1.0",
            "\n".join(
                [
                    "How To Use",
                    "",
                    "Step 1 - Start Here",
                    "Set your Base.wz folder path once and click 'Sync Base.wz To All Tabs'.",
                    "",
                    "Step 2 - Catalogue",
                    "Generate or load catalogue_all.csv, filter/search items by name, then apply selected IDs",
                    "into Render slots (weapon_id, cap_id, etc.).",
                    "",
                    "Step 3 - Render",
                    "Render one frame first to validate your build.",
                    "Recommended checks:",
                    "- Verify layer order with 'Z draw'.",
                    "- Confirm no unresolved assets in the render log.",
                    "",
                    "Step 4 - Batch Export",
                    "Export animation frames for one action or all actions.",
                    "Enable GIF and Sprite Sheet after single-frame render looks correct.",
                    "Quality filters help avoid broken frames:",
                    "- Skip unresolved assets",
                    "- Minimum drawn layers",
                    "",
                    "Step 5 - Diff (Optional)",
                    "Compare two Base.wz trees to find structural/composition/timing changes.",
                    "",
                    "Typical Workflow",
                    "1. Sync Base.wz",
                    "2. Generate/Load Catalogue",
                    "3. Apply IDs",
                    "4. Render single frame",
                    "5. Batch export GIF + sprite sheet",
                    "6. Use Diff only when comparing two versions",
                ]
            ),
        )
        guide_text.config(state="disabled")

    def _browse_dir(self, var: tk.StringVar) -> None:
        chosen = filedialog.askdirectory(initialdir=var.get() or ".")
        if chosen:
            var.set(chosen)

    def _browse_file_save(self, var: tk.StringVar, ext: str) -> None:
        chosen = filedialog.asksaveasfilename(
            defaultextension=ext,
            filetypes=[(f"{ext.upper()} files", f"*{ext}"), ("All files", "*.*")],
            initialfile=Path(var.get()).name if var.get() else None,
        )
        if chosen:
            var.set(chosen)

    def _browse_file_open(self, var: tk.StringVar, ext: str) -> None:
        chosen = filedialog.askopenfilename(
            filetypes=[(f"{ext.upper()} files", f"*{ext}"), ("All files", "*.*")],
            initialfile=Path(var.get()).name if var.get() else None,
        )
        if chosen:
            var.set(chosen)

    def _build_labeled_entry(
        self, parent: ttk.Frame, row: int, label: str, var: tk.StringVar, width: int = 42
    ) -> ttk.Entry:
        ttk.Label(parent, text=label).grid(row=row, column=0, sticky="w", padx=4, pady=4)
        ent = ttk.Entry(parent, textvariable=var, width=width)
        ent.grid(row=row, column=1, sticky="ew", padx=4, pady=4)
        return ent

    def _render_id_kwargs(self, starter_male: bool) -> dict:
        kwargs = {
            "base_id": int(self.base_id.get().strip()),
            "head_id": int(self.head_id.get().strip()),
            "face_id": int(self.face_id.get().strip()),
            "hair_id": int(self.hair_id.get().strip()),
            "accessory_id": int_or_none(self.accessory_id.get()),
            "cap_id": int_or_none(self.cap_id.get()),
            "coat_id": int_or_none(self.coat_id.get()),
            "longcoat_id": int_or_none(self.longcoat_id.get()),
            "pants_id": int_or_none(self.pants_id.get()),
            "shoes_id": int_or_none(self.shoes_id.get()),
            "glove_id": int_or_none(self.glove_id.get()),
            "cape_id": int_or_none(self.cape_id.get()),
            "shield_id": int_or_none(self.shield_id.get()),
            "weapon_id": int_or_none(self.weapon_id.get()),
        }
        if starter_male:
            kwargs["base_id"] = 2000
            kwargs["head_id"] = 12000
            if kwargs["coat_id"] is None:
                kwargs["coat_id"] = 1040002
            if kwargs["pants_id"] is None:
                kwargs["pants_id"] = 1060002
            if kwargs["shoes_id"] is None:
                kwargs["shoes_id"] = 1072001
            if kwargs["weapon_id"] is None:
                kwargs["weapon_id"] = 1302000
        return kwargs

    def _run_async(self, fn, on_done) -> None:
        def worker() -> None:
            try:
                result = fn()
                self.after(0, lambda: on_done(True, result))
            except Exception as exc:  # noqa: BLE001
                tb = traceback.format_exc()
                captured_exc = exc
                self.after(0, lambda: on_done(False, (captured_exc, tb)))

        threading.Thread(target=worker, daemon=True).start()

    def _load_eqp_name_index(self, base_wz: Path) -> dict[int, dict]:
        path_key = str(base_wz)
        if self._eqp_name_cache_path == path_key and self._eqp_name_index:
            return self._eqp_name_index

        idx = load_eqp_name_index(base_wz)
        self._eqp_name_cache_path = path_key
        self._eqp_name_index = idx
        return idx

    def _load_weapon_meta_index(self, base_wz: Path) -> dict[int, dict]:
        path_key = str(base_wz)
        if self._weapon_meta_cache_path == path_key and self._weapon_meta_index:
            return self._weapon_meta_index

        out = load_weapon_meta_index(base_wz, self._load_eqp_name_index(base_wz))
        self._weapon_meta_cache_path = path_key
        self._weapon_meta_index = out
        return out

    def _pick_weapon_for_class(self, base_wz: Path, class_name: str) -> Optional[dict]:
        body_actions = set(detect_actions(base_wz, int(self.base_id.get().strip() or "2000")))
        weapons = self._load_weapon_meta_index(base_wz)
        return pick_weapon_for_class(class_name, body_actions=body_actions, weapons=weapons)

    def on_apply_class_preset(self) -> None:
        class_name = self.render_class_preset.get().strip() or "Custom"
        if class_name == "Custom":
            self._append_render_log("Class preset set to Custom (manual control).")
            return

        base_wz = Path(self.render_base_wz.get().strip())
        base_err = validate_base_wz(base_wz)
        if base_err:
            messagebox.showerror("Class Preset Error", base_err)
            return

        picked = self._pick_weapon_for_class(base_wz, class_name)
        if not picked:
            messagebox.showerror(
                "Class Preset Error",
                f"No compatible weapon metadata/actions found for class '{class_name}'.",
            )
            return

        weapon_id = int(picked.get("item_id", 0))
        suggested_action = str(picked.get("suggested_action") or "stand1")
        self.weapon_id.set(str(weapon_id))
        self.render_action.set(suggested_action)
        self.batch_action.set(suggested_action)
        self.batch_action_source.set("loadout-intersection-with-weapon")

        name = str(picked.get("name") or f"{weapon_id}")
        req_job = int(picked.get("req_job", 0) or 0)
        req_level = int(picked.get("req_level", 0) or 0)
        self._append_render_log(
            f"Applied class preset '{class_name}': weapon={name} [{weapon_id}] "
            f"reqJob={req_job} reqLevel={req_level} action={suggested_action}"
        )

    # ---------------- Render tab ----------------
    def _build_render_tab(self) -> None:
        ttk.Label(
            self.render_tab,
            text="Step 3: Render one frame first, then move to Batch Export.",
        ).pack(anchor="w", padx=8, pady=(8, 0))

        top = ttk.Frame(self.render_tab)
        top.pack(fill="x", padx=8, pady=(4, 8))

        self.render_base_wz = tk.StringVar(value=DEFAULT_BASE_WZ)
        self.render_action = tk.StringVar(value="stand1")
        self.render_frame = tk.StringVar(value="0")
        self.render_out_png = tk.StringVar(
            value=str(Path(DEFAULT_ANALYSIS_DIR) / "renders" / "gui_render.png")
        )
        self.render_out_json = tk.StringVar(
            value=str(Path(DEFAULT_ANALYSIS_DIR) / "renders" / "gui_render.json")
        )
        self.render_starter_male = tk.BooleanVar(value=True)
        self.render_class_preset = tk.StringVar(value="Custom")
        self.render_cmd_preview = tk.StringVar(value="")
        self.render_z_draw_order = tk.StringVar(value="front-last")
        self.render_hair_mode = tk.StringVar(value="auto")
        self.render_live_preview = tk.BooleanVar(value=True)
        self.render_combo_path = tk.StringVar(
            value=str(Path(DEFAULT_ANALYSIS_DIR) / "combinations" / "last_combo.json")
        )

        self.base_id = tk.StringVar(value="2000")
        self.head_id = tk.StringVar(value="12000")
        self.face_id = tk.StringVar(value="20000")
        self.hair_id = tk.StringVar(value="30000")

        self.accessory_id = tk.StringVar(value="")
        self.cap_id = tk.StringVar(value="")
        self.coat_id = tk.StringVar(value="1040002")
        self.longcoat_id = tk.StringVar(value="")
        self.pants_id = tk.StringVar(value="1060002")
        self.shoes_id = tk.StringVar(value="1072001")
        self.glove_id = tk.StringVar(value="")
        self.cape_id = tk.StringVar(value="")
        self.shield_id = tk.StringVar(value="")
        self.weapon_id = tk.StringVar(value="1302000")

        self._build_labeled_entry(top, 0, "Base.wz path", self.render_base_wz, width=90)
        ttk.Button(
            top, text="Browse", command=lambda: self._browse_dir(self.render_base_wz)
        ).grid(row=0, column=2, padx=4, pady=4)

        self._build_labeled_entry(top, 1, "Action", self.render_action, width=20)
        self._build_labeled_entry(top, 2, "Frame", self.render_frame, width=20)
        class_row = ttk.Frame(top)
        class_row.grid(row=2, column=2, sticky="e", padx=4, pady=4)
        ttk.Label(class_row, text="Class Preset").pack(side="left")
        ttk.Combobox(
            class_row,
            textvariable=self.render_class_preset,
            values=list(CLASS_PRESET_DEFS.keys()),
            width=12,
            state="readonly",
        ).pack(side="left", padx=(6, 6))
        ttk.Button(class_row, text="Apply", command=self.on_apply_class_preset).pack(side="left")
        ttk.Checkbutton(top, text="Starter Male Body Preset (locks base/head only)", variable=self.render_starter_male).grid(
            row=3, column=1, sticky="w", padx=4, pady=4
        )
        z_row = ttk.Frame(top)
        z_row.grid(row=3, column=2, sticky="e", padx=4, pady=4)
        ttk.Label(z_row, text="Z draw").pack(side="left")
        ttk.Combobox(
            z_row,
            textvariable=self.render_z_draw_order,
            values=["front-last", "front-first"],
            width=12,
            state="readonly",
        ).pack(side="left", padx=(6, 0))
        ttk.Label(z_row, text="Hair mode").pack(side="left", padx=(10, 0))
        ttk.Combobox(
            z_row,
            textvariable=self.render_hair_mode,
            values=["auto", "force-show", "force-hide"],
            width=12,
            state="readonly",
        ).pack(side="left", padx=(6, 0))

        ids = ttk.LabelFrame(top, text="Part IDs")
        ids.grid(row=4, column=0, columnspan=3, sticky="ew", padx=4, pady=6)
        ids.columnconfigure(1, weight=1)
        ids.columnconfigure(4, weight=1)

        left_items = [
            ("base_id", self.base_id),
            ("head_id", self.head_id),
            ("face_id", self.face_id),
            ("hair_id", self.hair_id),
            ("accessory_id", self.accessory_id),
            ("cap_id", self.cap_id),
            ("coat_id", self.coat_id),
            ("longcoat_id", self.longcoat_id),
        ]
        right_items = [
            ("pants_id", self.pants_id),
            ("shoes_id", self.shoes_id),
            ("glove_id", self.glove_id),
            ("cape_id", self.cape_id),
            ("shield_id", self.shield_id),
            ("weapon_id", self.weapon_id),
        ]

        for idx, (label, var) in enumerate(left_items):
            ttk.Label(ids, text=label).grid(row=idx, column=0, sticky="w", padx=4, pady=3)
            ttk.Entry(ids, textvariable=var, width=16).grid(row=idx, column=1, sticky="w", padx=4, pady=3)
            ttk.Button(ids, text="Random", command=lambda s=label: self.on_randomize_slot(s)).grid(
                row=idx, column=2, sticky="w", padx=(2, 8), pady=3
            )
        for idx, (label, var) in enumerate(right_items):
            ttk.Label(ids, text=label).grid(row=idx, column=3, sticky="w", padx=4, pady=3)
            ttk.Entry(ids, textvariable=var, width=16).grid(row=idx, column=4, sticky="w", padx=4, pady=3)
            ttk.Button(ids, text="Random", command=lambda s=label: self.on_randomize_slot(s)).grid(
                row=idx, column=5, sticky="w", padx=(2, 8), pady=3
            )

        row_start = max(len(left_items), len(right_items))
        ttk.Button(ids, text="Randomize All Slots", command=self.on_randomize_all_slots).grid(
            row=row_start, column=0, columnspan=6, sticky="w", padx=4, pady=(6, 4)
        )

        ttk.Label(ids, text="Resolved Names (Name [ID])").grid(
            row=row_start + 1, column=0, columnspan=6, sticky="w", padx=4, pady=(6, 2)
        )
        self.id_name_preview = tk.Text(ids, height=6, wrap="word")
        self.id_name_preview.grid(row=row_start + 2, column=0, columnspan=6, sticky="ew", padx=4, pady=(0, 4))

        combo_row = ttk.Frame(ids)
        combo_row.grid(row=row_start + 3, column=0, columnspan=6, sticky="ew", padx=4, pady=(4, 2))
        combo_row.columnconfigure(1, weight=1)
        ttk.Label(combo_row, text="Combo Preset").grid(row=0, column=0, sticky="w", padx=(0, 6))
        ttk.Entry(combo_row, textvariable=self.render_combo_path, width=80).grid(
            row=0, column=1, sticky="ew", padx=(0, 6)
        )
        ttk.Button(combo_row, text="Browse", command=lambda: self._browse_file_open(self.render_combo_path, ".json")).grid(
            row=0, column=2, sticky="w", padx=(0, 6)
        )
        ttk.Button(combo_row, text="Save As", command=lambda: self._browse_file_save(self.render_combo_path, ".json")).grid(
            row=0, column=3, sticky="w", padx=(0, 6)
        )
        ttk.Button(combo_row, text="Save Combo", command=self.on_save_render_combo).grid(
            row=0, column=4, sticky="w", padx=(0, 6)
        )
        ttk.Button(combo_row, text="Load Combo", command=self.on_load_render_combo).grid(
            row=0, column=5, sticky="w"
        )

        self._build_labeled_entry(top, 5, "Output PNG", self.render_out_png, width=90)
        ttk.Button(
            top, text="Save As", command=lambda: self._browse_file_save(self.render_out_png, ".png")
        ).grid(row=5, column=2, padx=4, pady=4)

        self._build_labeled_entry(top, 6, "Output JSON", self.render_out_json, width=90)
        ttk.Button(
            top, text="Save As", command=lambda: self._browse_file_save(self.render_out_json, ".json")
        ).grid(row=6, column=2, padx=4, pady=4)

        btn_row = ttk.Frame(top)
        btn_row.grid(row=7, column=0, columnspan=3, sticky="w", padx=4, pady=8)
        self.render_btn = ttk.Button(btn_row, text="Render Frame", command=self.on_render)
        self.render_btn.pack(side="left", padx=(0, 8))
        self.diagnose_btn = ttk.Button(
            btn_row,
            text="Diagnose Hair/Cap",
            command=self.on_diagnose_hair_cap,
        )
        self.diagnose_btn.pack(side="left", padx=(0, 8))
        ttk.Checkbutton(
            btn_row,
            text="Auto-update preview",
            variable=self.render_live_preview,
            command=self._on_toggle_live_preview,
        ).pack(side="left", padx=(0, 8))
        ttk.Button(btn_row, text="Open Output Folder", command=self.on_open_render_folder).pack(
            side="left"
        )
        ttk.Label(top, text="Command Preview").grid(row=8, column=0, sticky="w", padx=4, pady=(8, 2))
        ttk.Entry(top, textvariable=self.render_cmd_preview, state="readonly", width=120).grid(
            row=9, column=0, columnspan=3, sticky="ew", padx=4, pady=(0, 6)
        )

        body = ttk.Panedwindow(self.render_tab, orient="horizontal")
        body.pack(fill="both", expand=True, padx=8, pady=(0, 8))

        left = ttk.Frame(body)
        right = ttk.Frame(body)
        body.add(left, weight=1)
        body.add(right, weight=1)

        ttk.Label(left, text="Render Log").pack(anchor="w")
        self.render_log = tk.Text(left, height=22, wrap="word")
        self.render_log.pack(fill="both", expand=True)

        ttk.Label(right, text="Image Preview").pack(anchor="w")
        self.preview_label = ttk.Label(right, text="No image rendered yet.")
        self.preview_label.pack(fill="both", expand=True, padx=8, pady=8)

        self._attach_render_traces()
        self._update_render_cmd_preview()
        self._schedule_live_preview_render(delay_ms=0)

    def _attach_render_traces(self) -> None:
        vars_to_trace = [
            self.render_base_wz,
            self.render_action,
            self.render_frame,
            self.render_out_png,
            self.render_out_json,
            self.render_starter_male,
            self.render_class_preset,
            self.render_z_draw_order,
            self.render_hair_mode,
            self.base_id,
            self.head_id,
            self.face_id,
            self.hair_id,
            self.accessory_id,
            self.cap_id,
            self.coat_id,
            self.longcoat_id,
            self.pants_id,
            self.shoes_id,
            self.glove_id,
            self.cape_id,
            self.shield_id,
            self.weapon_id,
        ]
        for v in vars_to_trace:
            v.trace_add("write", lambda *_: self._on_render_inputs_changed())
        self._update_resolved_id_names()

    def _on_render_inputs_changed(self) -> None:
        self._update_render_cmd_preview()
        self._update_resolved_id_names()
        self._schedule_live_preview_render()

    def _on_toggle_live_preview(self) -> None:
        if self.render_live_preview.get():
            self._schedule_live_preview_render(delay_ms=0)
        else:
            self._cancel_live_preview()

    def _cancel_live_preview(self) -> None:
        if self._live_preview_after_id is not None:
            try:
                self.after_cancel(self._live_preview_after_id)
            except Exception:  # noqa: BLE001
                pass
            self._live_preview_after_id = None
        self._live_preview_pending = False
        self._live_preview_token += 1

    def _schedule_live_preview_render(self, delay_ms: int = 250) -> None:
        if not hasattr(self, "render_live_preview") or not self.render_live_preview.get():
            return
        if self._live_preview_after_id is not None:
            try:
                self.after_cancel(self._live_preview_after_id)
            except Exception:  # noqa: BLE001
                pass
        self._live_preview_after_id = self.after(delay_ms, self._start_live_preview_render)

    def _collect_live_preview_kwargs(self) -> Optional[dict]:
        base_wz = Path(self.render_base_wz.get().strip())
        if validate_base_wz(base_wz):
            return None
        action = self.render_action.get().strip() or "stand1"
        try:
            frame = int((self.render_frame.get() or "0").strip())
            if frame < 0:
                return None
            kwargs = self._render_id_kwargs(self.render_starter_male.get())
        except Exception:  # noqa: BLE001
            return None

        live_png = Path(DEFAULT_ANALYSIS_DIR) / "renders" / "_live_preview.png"
        return {
            "base_wz": base_wz,
            "output_png": live_png,
            "action": action,
            "frame": frame,
            "output_json": None,
            "z_draw_order": self.render_z_draw_order.get(),
            "hair_mode": self.render_hair_mode.get(),
            **kwargs,
        }

    def _start_live_preview_render(self) -> None:
        self._live_preview_after_id = None
        if not self.render_live_preview.get():
            return
        if self._live_preview_running:
            self._live_preview_pending = True
            return

        kwargs = self._collect_live_preview_kwargs()
        if kwargs is None:
            return

        self._live_preview_running = True
        self._live_preview_token += 1
        token = self._live_preview_token

        def task():
            return render(**kwargs)

        def done(ok: bool, payload) -> None:
            stale = token != self._live_preview_token
            self._live_preview_running = False
            if not stale and ok:
                meta = payload
                self._update_preview(Path(meta["output_png"]))
            if self._live_preview_pending and self.render_live_preview.get():
                self._live_preview_pending = False
                self._schedule_live_preview_render(delay_ms=10)

        self._run_async(task, done)

    def _update_resolved_id_names(self) -> None:
        base = Path(self.render_base_wz.get())
        idx = self._load_eqp_name_index(base) if base.exists() else {}

        field_map = [
            ("face_id", self.face_id.get(), "Face"),
            ("hair_id", self.hair_id.get(), "Hair"),
            ("accessory_id", self.accessory_id.get(), "Accessory"),
            ("cap_id", self.cap_id.get(), "Cap"),
            ("coat_id", self.coat_id.get(), "Coat"),
            ("longcoat_id", self.longcoat_id.get(), "Longcoat"),
            ("pants_id", self.pants_id.get(), "Pants"),
            ("shoes_id", self.shoes_id.get(), "Shoes"),
            ("glove_id", self.glove_id.get(), "Glove"),
            ("cape_id", self.cape_id.get(), "Cape"),
            ("shield_id", self.shield_id.get(), "Shield"),
            ("weapon_id", self.weapon_id.get(), "Weapon"),
        ]

        lines = []
        for field_name, raw, expected_cat in field_map:
            raw = raw.strip()
            if not raw:
                continue
            if not raw.isdigit():
                lines.append(f"{field_name}: invalid id '{raw}'")
                continue
            item_id = int(raw)
            info = idx.get(item_id)
            if info:
                cat = info.get("category", "")
                name = info.get("name", "")
                if cat and cat != expected_cat:
                    lines.append(f"{field_name}: {name} [{item_id}] (category={cat}, expected={expected_cat})")
                else:
                    lines.append(f"{field_name}: {name} [{item_id}]")
            else:
                lines.append(f"{field_name}: Unknown [{item_id}]")

        if not lines:
            lines = ["No item IDs entered yet."]

        self.id_name_preview.config(state="normal")
        self.id_name_preview.delete("1.0", "end")
        self.id_name_preview.insert("end", "\n".join(lines))
        self.id_name_preview.config(state="disabled")

    def _render_combo_id_vars(self) -> dict[str, tk.StringVar]:
        return {
            "base_id": self.base_id,
            "head_id": self.head_id,
            "face_id": self.face_id,
            "hair_id": self.hair_id,
            "accessory_id": self.accessory_id,
            "cap_id": self.cap_id,
            "coat_id": self.coat_id,
            "longcoat_id": self.longcoat_id,
            "pants_id": self.pants_id,
            "shoes_id": self.shoes_id,
            "glove_id": self.glove_id,
            "cape_id": self.cape_id,
            "shield_id": self.shield_id,
            "weapon_id": self.weapon_id,
        }

    def _resolve_batch_character_out_dir(self, base_out_dir: Path, id_kwargs: Optional[dict] = None) -> tuple[Path, Optional[str]]:
        if not self.batch_use_character_folder.get():
            return base_out_dir, None
        if id_kwargs is None:
            id_kwargs = self._render_id_kwargs(self.batch_starter_male.get())
        return resolve_batch_character_out_dir(
            base_out_dir,
            id_kwargs,
            use_character_folder=self.batch_use_character_folder.get(),
            character_id_raw=self.batch_character_id.get().strip(),
        )

    def on_save_render_combo(self) -> None:
        combo_path_raw = self.render_combo_path.get().strip()
        if not combo_path_raw:
            self._browse_file_save(self.render_combo_path, ".json")
            combo_path_raw = self.render_combo_path.get().strip()
        if not combo_path_raw:
            return

        combo_path = Path(combo_path_raw)
        data = {
            "schema": "ms_character_combo_v1",
            "saved_at_utc": utc_now_iso(),
            "base_wz": self.render_base_wz.get().strip(),
            "action": self.render_action.get().strip(),
            "frame": self.render_frame.get().strip(),
            "starter_male": bool(self.render_starter_male.get()),
            "class_preset": self.render_class_preset.get().strip(),
            "z_draw_order": self.render_z_draw_order.get().strip(),
            "hair_mode": self.render_hair_mode.get().strip(),
            "ids": {name: var.get().strip() for name, var in self._render_combo_id_vars().items()},
        }
        try:
            combo_path.parent.mkdir(parents=True, exist_ok=True)
            combo_path.write_text(json.dumps(data, indent=2), encoding="utf-8")
            self._append_render_log(f"Saved combo preset: {combo_path}")
            messagebox.showinfo("Combo Saved", f"Saved preset to:\n{combo_path}")
        except Exception as exc:  # noqa: BLE001
            messagebox.showerror("Save Combo Failed", str(exc))

    def on_load_render_combo(self) -> None:
        combo_path_raw = self.render_combo_path.get().strip()
        if not combo_path_raw or not Path(combo_path_raw).exists():
            self._browse_file_open(self.render_combo_path, ".json")
            combo_path_raw = self.render_combo_path.get().strip()
        if not combo_path_raw:
            return

        combo_path = Path(combo_path_raw)
        if not combo_path.exists():
            messagebox.showerror("Load Combo Failed", f"Preset file not found:\n{combo_path}")
            return

        try:
            payload = json.loads(combo_path.read_text(encoding="utf-8"))
            if not isinstance(payload, dict):
                raise ValueError("Preset file must contain a JSON object.")

            ids_payload = payload.get("ids")
            if not isinstance(ids_payload, dict):
                ids_payload = payload

            loaded_fields = 0
            for name, var in self._render_combo_id_vars().items():
                if name in ids_payload:
                    raw = ids_payload.get(name)
                    var.set("" if raw is None else str(raw))
                    loaded_fields += 1

            if "base_wz" in payload:
                self.render_base_wz.set(str(payload.get("base_wz", "")))
                loaded_fields += 1
            if "action" in payload:
                self.render_action.set(str(payload.get("action", "")))
                loaded_fields += 1
            if "frame" in payload:
                self.render_frame.set(str(payload.get("frame", "")))
                loaded_fields += 1
            if "starter_male" in payload:
                self.render_starter_male.set(coerce_bool(payload.get("starter_male")))
                loaded_fields += 1
            class_raw = str(payload.get("class_preset", "")).strip()
            if class_raw in CLASS_PRESET_DEFS:
                self.render_class_preset.set(class_raw)
                loaded_fields += 1

            z_raw = str(payload.get("z_draw_order", "")).strip()
            if z_raw in {"front-last", "front-first"}:
                self.render_z_draw_order.set(z_raw)
                loaded_fields += 1
            hair_raw = str(payload.get("hair_mode", "")).strip()
            if hair_raw in {"auto", "force-show", "force-hide"}:
                self.render_hair_mode.set(hair_raw)
                loaded_fields += 1

            self._append_render_log(f"Loaded combo preset: {combo_path} (fields={loaded_fields})")
            messagebox.showinfo("Combo Loaded", f"Loaded preset from:\n{combo_path}")
        except Exception as exc:  # noqa: BLE001
            messagebox.showerror("Load Combo Failed", str(exc))

    def _update_render_cmd_preview(self) -> None:
        cmd = [
            "python",
            "tools/importers/render_character_frame.py",
            "--base-wz",
            f"\"{self.render_base_wz.get()}\"",
            "--action",
            self.render_action.get().strip() or "stand1",
            "--frame",
            self.render_frame.get().strip() or "0",
            "--output-png",
            f"\"{self.render_out_png.get()}\"",
        ]
        if self.render_out_json.get().strip():
            cmd.extend(["--output-json", f"\"{self.render_out_json.get()}\""])
        cmd.extend(["--z-draw-order", self.render_z_draw_order.get()])
        cmd.extend(["--hair-mode", self.render_hair_mode.get()])
        if self.render_starter_male.get():
            cmd.append("--starter-male")
        else:
            pairs = [
                ("--base-id", self.base_id.get()),
                ("--head-id", self.head_id.get()),
                ("--face-id", self.face_id.get()),
                ("--hair-id", self.hair_id.get()),
                ("--accessory-id", self.accessory_id.get()),
                ("--cap-id", self.cap_id.get()),
                ("--coat-id", self.coat_id.get()),
                ("--longcoat-id", self.longcoat_id.get()),
                ("--pants-id", self.pants_id.get()),
                ("--shoes-id", self.shoes_id.get()),
                ("--glove-id", self.glove_id.get()),
                ("--cape-id", self.cape_id.get()),
                ("--shield-id", self.shield_id.get()),
                ("--weapon-id", self.weapon_id.get()),
            ]
            for k, v in pairs:
                if v.strip():
                    cmd.extend([k, v.strip()])
        self.render_cmd_preview.set(" ".join(cmd))

    def on_open_render_folder(self) -> None:
        out = Path(self.render_out_png.get()).parent
        out.mkdir(parents=True, exist_ok=True)
        try:
            import os

            os.startfile(str(out))  # type: ignore[attr-defined]
        except Exception as exc:  # noqa: BLE001
            messagebox.showerror("Open Folder Error", str(exc))

    def _append_render_log(self, text: str) -> None:
        self.render_log.insert("end", text + "\n")
        self.render_log.see("end")

    def _collect_render_kwargs(self, output_png: Path, output_json: Optional[Path]) -> dict:
        base_wz = Path(self.render_base_wz.get().strip())
        base_err = validate_base_wz(base_wz)
        if base_err:
            raise ValueError(base_err)
        output_png_raw = self.render_out_png.get().strip()
        if not output_png_raw:
            raise ValueError("Output PNG path is required.")
        if output_png.suffix.lower() != ".png":
            raise ValueError("Output PNG path must end with .png")
        if output_png.exists() and output_png.is_dir():
            raise ValueError(f"Output PNG path is a directory, not a file: {output_png}")
        if output_json is not None:
            if output_json.suffix.lower() != ".json":
                raise ValueError("Output JSON path must end with .json")
            if output_json.exists() and output_json.is_dir():
                raise ValueError(f"Output JSON path is a directory, not a file: {output_json}")

        try:
            frame_int = int(self.render_frame.get().strip())
            if frame_int < 0:
                raise ValueError("Frame must be >= 0")
            int(self.base_id.get().strip())
            int(self.head_id.get().strip())
            int(self.face_id.get().strip())
            int(self.hair_id.get().strip())
            for optional in (
                self.accessory_id.get(),
                self.cap_id.get(),
                self.coat_id.get(),
                self.longcoat_id.get(),
                self.pants_id.get(),
                self.shoes_id.get(),
                self.glove_id.get(),
                self.cape_id.get(),
                self.shield_id.get(),
                self.weapon_id.get(),
            ):
                if optional.strip():
                    int(optional.strip())
        except Exception as exc:  # noqa: BLE001
            raise ValueError(f"Invalid numeric input: {exc}") from exc

        kwargs = {
            "base_wz": base_wz,
            "output_png": output_png,
            "action": self.render_action.get().strip() or "stand1",
            "frame": int(self.render_frame.get().strip()),
            "output_json": output_json,
            "z_draw_order": self.render_z_draw_order.get(),
            "hair_mode": self.render_hair_mode.get(),
        }
        kwargs.update(self._render_id_kwargs(self.render_starter_male.get()))
        return kwargs

    def _format_count_map(self, data: Optional[dict]) -> str:
        if not data:
            return "(none)"
        parts = []
        for key in sorted(data.keys()):
            parts.append(f"{key}:{data[key]}")
        return ", ".join(parts)

    def _log_hair_cap_diagnostic(self, meta: dict) -> None:
        hp = meta.get("hair_policy", {}) or {}
        cap_state = hp.get("cap_state", {}) or {}
        draw_order = meta.get("draw_order", []) or []
        action_resolution = meta.get("action_resolution", []) or []
        unresolved = meta.get("unresolved", []) or []

        self._append_render_log("=== Hair/Cap Diagnostic ===")
        self._append_render_log(
            (
                f"Action={meta.get('action')} Frame={meta.get('frame')} "
                f"HairMode={hp.get('mode', 'unknown')} Rule={hp.get('rule', 'none')}"
            )
        )
        self._append_render_log(
            (
                "Removed hair layers="
                f"{hp.get('removed_layers', 0)} "
                f"(front={hp.get('removed_front_hair_layers', 0)}, "
                f"back={hp.get('removed_back_hair_layers', 0)})"
            )
        )
        self._append_render_log(
            (
                "Hair layer counts="
                f"total:{hp.get('hair_layers_total', '?')} "
                f"kept:{hp.get('hair_layers_kept', '?')}"
            )
        )
        self._append_render_log(f"Hair Z total: {format_count_map(hp.get('hair_z_total'))}")
        self._append_render_log(f"Hair Z kept: {format_count_map(hp.get('hair_z_kept'))}")
        self._append_render_log(f"Hair Z removed: {format_count_map(hp.get('hair_z_removed'))}")
        self._append_render_log(
            (
                "Cap state: "
                f"has_cap={cap_state.get('has_cap')} "
                f"full_mask={cap_state.get('full_hair_mask')} "
                f"partial_mask={cap_state.get('partial_hair_mask')} "
                f"front_over={cap_state.get('cap_front_over_hair')} "
                f"back_over={cap_state.get('cap_back_over_hair')} "
                f"tokens={cap_state.get('hair_tokens', [])}"
            )
        )
        vslot = str(cap_state.get("vslot", "")).strip()
        self._append_render_log(f"Cap vslot: {vslot if vslot else '(empty)'}")

        removed_examples = hp.get("removed_examples", []) or []
        if removed_examples:
            self._append_render_log("Removed hair examples:")
            for row in removed_examples[:8]:
                self._append_render_log(
                    f"  - z={row.get('z')} node={row.get('node_path')} part={row.get('part_id')}"
                )
            if hp.get("removed_examples_truncated"):
                self._append_render_log("  - ... (truncated)")

        cap_z = {}
        hair_z = {}
        for row in draw_order:
            kind = row.get("asset_kind")
            z = str(row.get("z", "unknown"))
            if kind == "cap":
                cap_z[z] = cap_z.get(z, 0) + 1
            elif kind == "hair":
                hair_z[z] = hair_z.get(z, 0) + 1
        self._append_render_log(f"Drawn cap Z: {format_count_map(cap_z)}")
        self._append_render_log(f"Drawn hair Z: {format_count_map(hair_z)}")

        focus_rows = []
        for row in action_resolution:
            if row.get("asset_kind") not in ("hair", "cap", "face", "head"):
                continue
            mode = str(row.get("selection_mode", ""))
            if mode not in ("exact_action_exact_frame",):
                focus_rows.append(row)
        if focus_rows:
            self._append_render_log("Action/frame fallbacks affecting head stack:")
            for row in focus_rows[:8]:
                self._append_render_log(
                    (
                        f"  - {row.get('asset_kind')}[{row.get('part_id')}]: "
                        f"requested={row.get('requested_action')}:{row.get('requested_frame')} "
                        f"selected={row.get('selected_action')}:{row.get('selected_frame')} "
                        f"mode={row.get('selection_mode')}"
                    )
                )

        self._append_render_log(f"Unresolved entries: {len(unresolved)}")
        if unresolved:
            for row in unresolved[:5]:
                self._append_render_log(f"  - {row}")
            if len(unresolved) > 5:
                self._append_render_log("  - ... (truncated)")
        self._append_render_log("=== End Diagnostic ===")

    def on_render(self) -> None:
        self._cancel_live_preview()
        try:
            kwargs = self._collect_render_kwargs(
                output_png=Path(self.render_out_png.get()),
                output_json=Path(self.render_out_json.get()) if self.render_out_json.get().strip() else None,
            )
        except Exception as exc:  # noqa: BLE001
            messagebox.showerror("Validation Error", str(exc))
            return
        if self.coat_id.get().strip() and self.longcoat_id.get().strip():
            self._append_render_log("Warning: both coat and longcoat are set; layering conflicts may occur.")

        self.render_btn.config(state="disabled")
        self.diagnose_btn.config(state="disabled")
        self._append_render_log("Starting render...")

        def task():
            return render(**kwargs)

        def done(ok: bool, payload) -> None:
            self.render_btn.config(state="normal")
            self.diagnose_btn.config(state="normal")
            if not ok:
                exc, tb = payload
                self._append_render_log(f"Render failed: {exc}")
                self._append_render_log(tb)
                messagebox.showerror("Render Failed", str(exc))
                return

            meta = payload
            self._append_render_log(
                f"Render complete: layers={meta['drawn_layers']} unresolved={len(meta['unresolved'])}"
            )
            self._append_render_log(json.dumps(meta, indent=2))
            self._update_preview(Path(meta["output_png"]))

        self._run_async(task, done)

    def on_diagnose_hair_cap(self) -> None:
        self._cancel_live_preview()
        diag_png = Path(DEFAULT_ANALYSIS_DIR) / "renders" / "_diagnostic_render.png"
        try:
            kwargs = self._collect_render_kwargs(output_png=diag_png, output_json=None)
        except Exception as exc:  # noqa: BLE001
            messagebox.showerror("Validation Error", str(exc))
            return

        self.diagnose_btn.config(state="disabled")
        self._append_render_log("Running hair/cap diagnostic...")

        def task():
            return render(**kwargs)

        def done(ok: bool, payload) -> None:
            self.diagnose_btn.config(state="normal")
            if not ok:
                exc, tb = payload
                self._append_render_log(f"Diagnostic failed: {exc}")
                self._append_render_log(tb)
                messagebox.showerror("Diagnostic Failed", str(exc))
                return
            meta = payload
            self._update_preview(Path(meta["output_png"]))
            self._log_hair_cap_diagnostic(meta)

        self._run_async(task, done)

    def _update_preview(
        self,
        image_path: Path,
        target_label: Optional[ttk.Label] = None,
        max_size: tuple[int, int] = (520, 520),
        cache_attr: str = "image_preview",
    ) -> None:
        label = target_label if target_label is not None else self.preview_label
        if not image_path.exists():
            label.config(image="", text=f"Image not found: {image_path}")
            if hasattr(self, "global_preview_label"):
                self.global_preview_label.config(image="", text=f"Image not found: {image_path}")
                self.global_preview_status.set("Preview missing on disk.")
            return
        with Image.open(image_path) as base_im:
            pil = base_im.convert("RGBA")
        pil.thumbnail(max_size, Image.Resampling.NEAREST)
        photo = ImageTk.PhotoImage(pil)
        setattr(self, cache_attr, photo)
        label.config(image=photo, text="")

        if hasattr(self, "global_preview_label"):
            with Image.open(image_path) as dock_base_im:
                dock_img = dock_base_im.convert("RGBA")
            dock_img.thumbnail((340, 340), Image.Resampling.NEAREST)
            self.global_preview_image = ImageTk.PhotoImage(dock_img)
            self.global_preview_label.config(image=self.global_preview_image, text="")
            self.global_preview_path = image_path
            self.global_preview_status.set(f"Showing: {image_path}")

    # ---------------- Diff tab ----------------
    def _build_diff_tab(self) -> None:
        ttk.Label(
            self.diff_tab,
            text="Step 5 (Optional): Diff two Base.wz trees when comparing versions.",
        ).pack(anchor="w", padx=8, pady=(8, 0))

        top = ttk.Frame(self.diff_tab)
        top.pack(fill="x", padx=8, pady=(4, 8))

        self.diff_old = tk.StringVar(value=DEFAULT_BASE_WZ)
        self.diff_new = tk.StringVar(value=DEFAULT_BASE_WZ)
        self.diff_out = tk.StringVar(value=str(Path(DEFAULT_ANALYSIS_DIR) / "diff_gui"))
        self.diff_xml_compare = tk.StringVar(value="size")
        self.diff_png_compare = tk.StringVar(value="size")
        self.diff_include_unchanged = tk.BooleanVar(value=False)
        self.diff_skip_png = tk.BooleanVar(value=False)
        self.diff_cmd_preview = tk.StringVar(value="")

        self._build_labeled_entry(top, 0, "Old Base.wz", self.diff_old, width=90)
        ttk.Button(top, text="Browse", command=lambda: self._browse_dir(self.diff_old)).grid(
            row=0, column=2, padx=4, pady=4
        )
        self._build_labeled_entry(top, 1, "New Base.wz", self.diff_new, width=90)
        ttk.Button(top, text="Browse", command=lambda: self._browse_dir(self.diff_new)).grid(
            row=1, column=2, padx=4, pady=4
        )
        self._build_labeled_entry(top, 2, "Output Dir", self.diff_out, width=90)
        ttk.Button(top, text="Browse", command=lambda: self._browse_dir(self.diff_out)).grid(
            row=2, column=2, padx=4, pady=4
        )

        opts = ttk.Frame(top)
        opts.grid(row=3, column=0, columnspan=3, sticky="w", padx=4, pady=6)
        ttk.Label(opts, text="XML compare").pack(side="left")
        ttk.Combobox(
            opts, textvariable=self.diff_xml_compare, values=["size", "hash"], width=8, state="readonly"
        ).pack(side="left", padx=(6, 20))
        ttk.Label(opts, text="PNG compare").pack(side="left")
        self.diff_png_combo = ttk.Combobox(
            opts, textvariable=self.diff_png_compare, values=["size", "hash"], width=8, state="readonly"
        )
        self.diff_png_combo.pack(side="left", padx=(6, 20))
        ttk.Checkbutton(opts, text="Include unchanged", variable=self.diff_include_unchanged).pack(
            side="left", padx=(0, 16)
        )
        ttk.Checkbutton(opts, text="Skip PNG", variable=self.diff_skip_png).pack(side="left")

        btn_row = ttk.Frame(top)
        btn_row.grid(row=4, column=0, columnspan=3, sticky="w", padx=4, pady=8)
        self.diff_btn = ttk.Button(btn_row, text="Run Diff", command=self.on_diff)
        self.diff_btn.pack(side="left", padx=(0, 8))
        ttk.Button(btn_row, text="Open Output Folder", command=self.on_open_diff_folder).pack(side="left")

        ttk.Label(top, text="Command Preview").grid(row=5, column=0, sticky="w", padx=4, pady=(8, 2))
        ttk.Entry(top, textvariable=self.diff_cmd_preview, state="readonly", width=120).grid(
            row=6, column=0, columnspan=3, sticky="ew", padx=4, pady=(0, 6)
        )

        ttk.Label(self.diff_tab, text="Diff Log").pack(anchor="w", padx=8)
        self.diff_log = tk.Text(self.diff_tab, height=28, wrap="word")
        self.diff_log.pack(fill="both", expand=True, padx=8, pady=(0, 8))

        self._attach_diff_traces()
        self._toggle_png_compare_state()
        self._update_diff_cmd_preview()

    def _attach_diff_traces(self) -> None:
        for v in (
            self.diff_old,
            self.diff_new,
            self.diff_out,
            self.diff_xml_compare,
            self.diff_png_compare,
            self.diff_include_unchanged,
            self.diff_skip_png,
        ):
            v.trace_add("write", lambda *_: self._on_diff_var_change())

    def _on_diff_var_change(self) -> None:
        self._toggle_png_compare_state()
        self._update_diff_cmd_preview()

    def _toggle_png_compare_state(self) -> None:
        if self.diff_skip_png.get():
            self.diff_png_combo.state(["disabled"])
        else:
            self.diff_png_combo.state(["!disabled"])

    def _update_diff_cmd_preview(self) -> None:
        cmd = [
            "python",
            "tools/importers/diff_character_assets.py",
            "--old-base-wz",
            f"\"{self.diff_old.get()}\"",
            "--new-base-wz",
            f"\"{self.diff_new.get()}\"",
            "--output-dir",
            f"\"{self.diff_out.get()}\"",
            "--xml-compare",
            self.diff_xml_compare.get(),
        ]
        if not self.diff_skip_png.get():
            cmd.extend(["--png-compare", self.diff_png_compare.get()])
        else:
            cmd.append("--skip-png")
        if self.diff_include_unchanged.get():
            cmd.append("--include-unchanged")
        self.diff_cmd_preview.set(" ".join(cmd))

    def on_open_diff_folder(self) -> None:
        out = Path(self.diff_out.get())
        out.mkdir(parents=True, exist_ok=True)
        try:
            import os

            os.startfile(str(out))  # type: ignore[attr-defined]
        except Exception as exc:  # noqa: BLE001
            messagebox.showerror("Open Folder Error", str(exc))

    def _append_diff_log(self, text: str) -> None:
        self.diff_log.insert("end", text + "\n")
        self.diff_log.see("end")

    def on_diff(self) -> None:
        old_path = Path(self.diff_old.get())
        new_path = Path(self.diff_new.get())
        old_err = validate_base_wz(old_path)
        if old_err:
            messagebox.showerror("Validation Error", f"Old path invalid: {old_err}")
            return
        new_err = validate_base_wz(new_path)
        if new_err:
            messagebox.showerror("Validation Error", f"New path invalid: {new_err}")
            return
        if old_path.resolve() == new_path.resolve():
            self._append_diff_log("Warning: old and new paths are identical; diff will use identity shortcut.")
        if self.diff_xml_compare.get() == "hash" or (
            not self.diff_skip_png.get() and self.diff_png_compare.get() == "hash"
        ):
            self._append_diff_log("Warning: hash mode may be slow on large trees.")
        if self.diff_include_unchanged.get():
            self._append_diff_log("Warning: include-unchanged may generate large CSV outputs.")

        self.diff_btn.config(state="disabled")
        self._append_diff_log("Starting diff...")

        def task():
            return diff_character_trees(
                old_base_wz=Path(self.diff_old.get()),
                new_base_wz=Path(self.diff_new.get()),
                output_dir=Path(self.diff_out.get()),
                xml_compare=self.diff_xml_compare.get(),
                png_compare=self.diff_png_compare.get(),
                include_unchanged=self.diff_include_unchanged.get(),
                skip_png=self.diff_skip_png.get(),
            )

        def done(ok: bool, payload) -> None:
            self.diff_btn.config(state="normal")
            if not ok:
                exc, tb = payload
                self._append_diff_log(f"Diff failed: {exc}")
                self._append_diff_log(tb)
                messagebox.showerror("Diff Failed", str(exc))
                return

            summary = payload
            self._append_diff_log("Diff complete.")
            self._append_diff_log(json.dumps(summary, indent=2))

        self._run_async(task, done)

    # ---------------- Batch tab ----------------
    def _build_batch_tab(self) -> None:
        ttk.Label(
            self.batch_tab,
            text="Step 4: Export full animations after single-frame render is correct.",
        ).pack(anchor="w", padx=8, pady=(8, 0))

        top = ttk.Frame(self.batch_tab)
        top.pack(fill="x", padx=8, pady=(4, 8))

        self.batch_base_wz = tk.StringVar(value=DEFAULT_BASE_WZ)
        self.batch_action = tk.StringVar(value="walk1")
        self.batch_start = tk.StringVar(value="0")
        self.batch_end = tk.StringVar(value="3")
        self.batch_output_dir = tk.StringVar(value=str(Path(DEFAULT_ANALYSIS_DIR) / "batch_exports"))
        self.batch_prefix = tk.StringVar(value="anim")
        self.batch_use_character_folder = tk.BooleanVar(value=True)
        self.batch_character_id = tk.StringVar(value="")
        self.batch_starter_male = tk.BooleanVar(value=True)
        self.batch_z_draw_order = tk.StringVar(value="front-last")
        self.batch_hair_mode = tk.StringVar(value="auto")
        self.batch_auto_frames = tk.BooleanVar(value=True)
        self.batch_all_actions = tk.BooleanVar(value=False)
        self.batch_action_source = tk.StringVar(value="loadout-intersection-with-weapon")
        self.batch_use_action_delays = tk.BooleanVar(value=True)
        self.batch_normalize_canvas = tk.BooleanVar(value=True)
        self.batch_write_json = tk.BooleanVar(value=True)
        self.batch_make_gif = tk.BooleanVar(value=True)
        self.batch_gif_path = tk.StringVar(value=str(Path(DEFAULT_ANALYSIS_DIR) / "batch_exports" / "anim.gif"))
        self.batch_gif_duration = tk.StringVar(value="120")
        self.batch_make_sheet = tk.BooleanVar(value=True)
        self.batch_sheet_path = tk.StringVar(
            value=str(Path(DEFAULT_ANALYSIS_DIR) / "batch_exports" / "anim_sheet.png")
        )
        self.batch_sheet_cols = tk.StringVar(value="8")
        self.batch_skip_unresolved = tk.BooleanVar(value=True)
        self.batch_min_layers = tk.StringVar(value="8")
        self.batch_skill_id = tk.StringVar(value="")
        self.batch_skill_anim = tk.StringVar(value="auto")
        self.batch_cmd_preview = tk.StringVar(value="")

        self._build_labeled_entry(top, 0, "Base.wz path", self.batch_base_wz, width=90)
        ttk.Button(top, text="Browse", command=lambda: self._browse_dir(self.batch_base_wz)).grid(
            row=0, column=2, padx=4, pady=4
        )
        self._build_labeled_entry(top, 1, "Action", self.batch_action, width=24)
        self._build_labeled_entry(top, 2, "Start Frame", self.batch_start, width=12)
        self._build_labeled_entry(top, 3, "End Frame", self.batch_end, width=12)
        self._build_labeled_entry(top, 4, "Output Dir", self.batch_output_dir, width=90)
        ttk.Button(top, text="Browse", command=lambda: self._browse_dir(self.batch_output_dir)).grid(
            row=4, column=2, padx=4, pady=4
        )
        self._build_labeled_entry(top, 5, "File Prefix", self.batch_prefix, width=24)
        out_scope = ttk.Frame(top)
        out_scope.grid(row=5, column=2, sticky="e", padx=4, pady=4)
        ttk.Checkbutton(
            out_scope,
            text="Per-character folder",
            variable=self.batch_use_character_folder,
        ).pack(side="left")
        ttk.Label(out_scope, text="ID").pack(side="left", padx=(8, 4))
        ttk.Entry(out_scope, textvariable=self.batch_character_id, width=12).pack(side="left")
        ttk.Checkbutton(top, text="Starter Male Body Preset (uses Render IDs for face/hair)", variable=self.batch_starter_male).grid(
            row=6, column=1, sticky="w", padx=4, pady=2
        )
        z_opts = ttk.Frame(top)
        z_opts.grid(row=6, column=2, sticky="e", padx=4, pady=2)
        ttk.Label(z_opts, text="Z draw").pack(side="left")
        ttk.Combobox(
            z_opts,
            textvariable=self.batch_z_draw_order,
            values=["front-last", "front-first"],
            width=12,
            state="readonly",
        ).pack(side="left", padx=(6, 0))
        ttk.Label(z_opts, text="Hair mode").pack(side="left", padx=(10, 0))
        ttk.Combobox(
            z_opts,
            textvariable=self.batch_hair_mode,
            values=["auto", "force-show", "force-hide"],
            width=12,
            state="readonly",
        ).pack(side="left", padx=(6, 0))
        ttk.Checkbutton(top, text="Auto-detect full action frames", variable=self.batch_auto_frames).grid(
            row=7, column=1, sticky="w", padx=4, pady=2
        )
        ttk.Checkbutton(top, text="Export all actions", variable=self.batch_all_actions).grid(
            row=7, column=2, sticky="w", padx=4, pady=2
        )
        action_src = ttk.Frame(top)
        action_src.grid(row=7, column=0, sticky="w", padx=4, pady=2)
        ttk.Label(action_src, text="All-actions source").pack(side="left")
        ttk.Combobox(
            action_src,
            textvariable=self.batch_action_source,
            values=["loadout-intersection-with-weapon", "loadout-intersection", "body-only"],
            width=22,
            state="readonly",
        ).pack(side="left", padx=(6, 0))
        ttk.Checkbutton(top, text="Write per-frame JSON metadata", variable=self.batch_write_json).grid(
            row=8, column=1, sticky="w", padx=4, pady=2
        )
        ttk.Checkbutton(top, text="Use in-game frame delays (GIF timing)", variable=self.batch_use_action_delays).grid(
            row=8, column=0, sticky="w", padx=4, pady=2
        )
        ttk.Checkbutton(top, text="Create GIF", variable=self.batch_make_gif).grid(
            row=8, column=2, sticky="w", padx=4, pady=2
        )
        ttk.Checkbutton(top, text="Normalize frame canvas per action", variable=self.batch_normalize_canvas).grid(
            row=9, column=0, sticky="w", padx=4, pady=2
        )
        self._build_labeled_entry(top, 9, "GIF Path (single-action mode)", self.batch_gif_path, width=90)
        ttk.Button(top, text="Save As", command=lambda: self._browse_file_save(self.batch_gif_path, ".gif")).grid(
            row=9, column=2, padx=4, pady=4
        )
        self._build_labeled_entry(top, 10, "GIF Frame Duration (ms)", self.batch_gif_duration, width=12)
        ttk.Checkbutton(top, text="Create Sprite Sheet", variable=self.batch_make_sheet).grid(
            row=10, column=2, sticky="w", padx=4, pady=2
        )
        self._build_labeled_entry(top, 11, "Sprite Sheet Path (single-action mode)", self.batch_sheet_path, width=90)
        ttk.Button(top, text="Save As", command=lambda: self._browse_file_save(self.batch_sheet_path, ".png")).grid(
            row=11, column=2, padx=4, pady=4
        )
        self._build_labeled_entry(top, 12, "Sprite Sheet Columns", self.batch_sheet_cols, width=12)
        ttk.Checkbutton(top, text="Skip frames with unresolved assets", variable=self.batch_skip_unresolved).grid(
            row=12, column=2, sticky="w", padx=4, pady=2
        )
        self._build_labeled_entry(top, 13, "Minimum drawn layers per frame", self.batch_min_layers, width=12)
        self._build_labeled_entry(top, 14, "Skill ID (optional overlay)", self.batch_skill_id, width=16)
        skill_opts = ttk.Frame(top)
        skill_opts.grid(row=14, column=2, sticky="e", padx=4, pady=4)
        ttk.Label(skill_opts, text="Skill Anim").pack(side="left")
        ttk.Combobox(
            skill_opts,
            textvariable=self.batch_skill_anim,
            values=["auto", "effect", "effect0", "effect1", "hit", "ball", "prepare", "summon", "affected"],
            width=12,
            state="readonly",
        ).pack(side="left", padx=(6, 0))

        btn_row = ttk.Frame(top)
        btn_row.grid(row=15, column=0, columnspan=3, sticky="w", padx=4, pady=8)
        self.batch_btn = ttk.Button(btn_row, text="Export Batch", command=self.on_batch_export)
        self.batch_btn.pack(side="left", padx=(0, 8))
        ttk.Button(btn_row, text="Open Output Folder", command=self.on_open_batch_folder).pack(side="left", padx=(0, 8))
        self.batch_audit_btn = ttk.Button(btn_row, text="Run Alignment Audit", command=self.on_run_alignment_audit)
        self.batch_audit_btn.pack(side="left")

        ttk.Label(top, text="Command Preview").grid(row=16, column=0, sticky="w", padx=4, pady=(8, 2))
        ttk.Entry(top, textvariable=self.batch_cmd_preview, state="readonly", width=120).grid(
            row=17, column=0, columnspan=3, sticky="ew", padx=4, pady=(0, 6)
        )

        ttk.Label(self.batch_tab, text="Batch Log").pack(anchor="w", padx=8)
        self.batch_log = tk.Text(self.batch_tab, height=28, wrap="word")
        self.batch_log.pack(fill="both", expand=True, padx=8, pady=(0, 8))

        for v in (
            self.batch_base_wz,
            self.batch_action,
            self.batch_start,
            self.batch_end,
            self.batch_output_dir,
            self.batch_prefix,
            self.batch_use_character_folder,
            self.batch_character_id,
            self.batch_starter_male,
            self.batch_z_draw_order,
            self.batch_hair_mode,
            self.batch_auto_frames,
            self.batch_all_actions,
            self.batch_action_source,
            self.batch_use_action_delays,
            self.batch_normalize_canvas,
            self.batch_write_json,
            self.batch_make_gif,
            self.batch_gif_path,
            self.batch_gif_duration,
            self.batch_make_sheet,
            self.batch_sheet_path,
            self.batch_sheet_cols,
            self.batch_skip_unresolved,
            self.batch_min_layers,
            self.batch_skill_id,
            self.batch_skill_anim,
        ):
            v.trace_add("write", lambda *_: self._update_batch_cmd_preview())
        self._update_batch_cmd_preview()

    def _update_batch_cmd_preview(self) -> None:
        cmd = [
            "batch_export",
            "--base-wz",
            f"\"{self.batch_base_wz.get()}\"",
            "--action",
            self.batch_action.get().strip() or "walk1",
            "--output-dir",
            f"\"{self.batch_output_dir.get()}\"",
            "--prefix",
            self.batch_prefix.get().strip() or "anim",
        ]
        if self.batch_all_actions.get():
            cmd.append("--all-actions")
            cmd.extend(["--all-actions-source", self.batch_action_source.get()])
        if self.batch_auto_frames.get():
            cmd.append("--auto-frames")
        else:
            cmd.extend(
                [
                    "--frames",
                    f"{self.batch_start.get().strip() or '0'}:{self.batch_end.get().strip() or '0'}",
                ]
            )
        if self.batch_starter_male.get():
            cmd.append("--starter-male")
        if self.batch_use_action_delays.get():
            cmd.append("--use-action-delays")
        if self.batch_normalize_canvas.get():
            cmd.append("--normalize-canvas")
        if self.batch_use_character_folder.get():
            cmd.append("--per-character-folder")
            if self.batch_character_id.get().strip():
                cmd.extend(["--character-id", self.batch_character_id.get().strip()])
        cmd.extend(["--z-draw-order", self.batch_z_draw_order.get()])
        cmd.extend(["--hair-mode", self.batch_hair_mode.get()])
        if self.batch_write_json.get():
            cmd.append("--write-json")
        if self.batch_make_gif.get():
            cmd.extend(
                [
                    "--gif",
                    f"\"{self.batch_gif_path.get()}\"",
                    "--gif-duration",
                    self.batch_gif_duration.get().strip() or "120",
                ]
            )
        if self.batch_make_sheet.get():
            cmd.extend(
                [
                    "--sprite-sheet",
                    f"\"{self.batch_sheet_path.get()}\"",
                    "--sheet-cols",
                    self.batch_sheet_cols.get().strip() or "8",
                ]
            )
        if self.batch_skip_unresolved.get():
            cmd.append("--skip-unresolved")
        cmd.extend(["--min-layers", self.batch_min_layers.get().strip() or "8"])
        skill_id_raw = self.batch_skill_id.get().strip()
        if skill_id_raw:
            cmd.extend(["--skill-id", skill_id_raw])
            cmd.extend(["--skill-anim", self.batch_skill_anim.get().strip() or "auto"])
        self.batch_cmd_preview.set(" ".join(cmd))

    def _append_batch_log(self, text: str) -> None:
        self.batch_log.insert("end", text + "\n")
        self.batch_log.see("end")

    def on_open_batch_folder(self) -> None:
        base_out = Path(self.batch_output_dir.get())
        base_out.mkdir(parents=True, exist_ok=True)
        try:
            id_kwargs = self._render_id_kwargs(self.batch_starter_male.get())
            out, _ = self._resolve_batch_character_out_dir(base_out, id_kwargs=id_kwargs)
        except Exception:  # noqa: BLE001
            out = base_out
        out.mkdir(parents=True, exist_ok=True)
        try:
            import os

            os.startfile(str(out))  # type: ignore[attr-defined]
        except Exception as exc:  # noqa: BLE001
            messagebox.showerror("Open Folder Error", str(exc))

    def on_run_alignment_audit(self) -> None:
        base_wz = Path(self.batch_base_wz.get().strip())
        base_err = validate_base_wz(base_wz)
        if base_err:
            messagebox.showerror("Validation Error", base_err)
            return

        prefix = self.batch_prefix.get().strip()
        if not prefix:
            messagebox.showerror("Validation Error", "File prefix is required.")
            return

        base_out_dir = Path(self.batch_output_dir.get().strip())
        try:
            id_kwargs = self._render_id_kwargs(self.batch_starter_male.get())
            out_dir, _ = self._resolve_batch_character_out_dir(base_out_dir, id_kwargs=id_kwargs)
        except Exception:  # noqa: BLE001
            out_dir = base_out_dir
        if self.batch_all_actions.get():
            summary_path = out_dir / f"{prefix}_all_actions_batch_summary.json"
        else:
            action = self.batch_action.get().strip()
            if not action:
                messagebox.showerror("Validation Error", "Action is required for single-action audit.")
                return
            summary_path = out_dir / f"{prefix}_{action}_batch_summary.json"

        if not summary_path.exists():
            messagebox.showerror(
                "Audit Error",
                (
                    "Batch summary not found. Run Batch Export first, or check Output Dir / Prefix / mode.\n"
                    f"Expected: {summary_path}"
                ),
            )
            return

        audit_out = out_dir / "alignment_audit"
        self.batch_audit_btn.config(state="disabled")
        self._append_batch_log(f"Running alignment audit: {summary_path}")

        def task():
            return run_alignment_audit(
                batch_summary_path=summary_path,
                base_wz=base_wz,
                out_dir=audit_out,
                max_jitter_px=10.0,
                max_fallback_rate=0.35,
                allow_origin_fallback_kinds=("body",),
            )

        def done(ok: bool, payload) -> None:
            self.batch_audit_btn.config(state="normal")
            if not ok:
                exc, tb = payload
                self._append_batch_log(f"Alignment audit failed: {exc}")
                self._append_batch_log(tb)
                messagebox.showerror("Alignment Audit Failed", str(exc))
                return
            result = payload
            self._append_batch_log("Alignment audit complete.")
            self._append_batch_log(json.dumps(result, indent=2))
            messagebox.showinfo(
                "Alignment Audit Complete",
                (
                    f"Summary: {result.get('summary_md')}\n"
                    f"Report: {result.get('report_path')}\n"
                    f"Findings CSV: {result.get('findings_csv')}"
                ),
            )

        self._run_async(task, done)

    def on_batch_export(self) -> None:
        base_wz = Path(self.batch_base_wz.get())
        base_err = validate_base_wz(base_wz)
        if base_err:
            messagebox.showerror("Validation Error", base_err)
            return
        try:
            start = int(self.batch_start.get().strip())
            end = int(self.batch_end.get().strip())
            if start < 0 or end < 0 or end < start:
                raise ValueError("Require 0 <= start <= end")
            gif_duration = int(self.batch_gif_duration.get().strip() or "120")
            if gif_duration <= 0:
                raise ValueError("GIF duration must be > 0")
            sheet_cols = int(self.batch_sheet_cols.get().strip() or "8")
            if sheet_cols <= 0:
                raise ValueError("Sprite sheet columns must be > 0")
            min_layers = int(self.batch_min_layers.get().strip() or "8")
            if min_layers <= 0:
                raise ValueError("Minimum layers must be > 0")
            skill_id_raw = self.batch_skill_id.get().strip()
            if skill_id_raw:
                skill_id_int = int(skill_id_raw)
                if skill_id_int <= 0:
                    raise ValueError("Skill ID must be > 0")
            char_id_raw = self.batch_character_id.get().strip()
            if char_id_raw and not char_id_raw.isdigit():
                raise ValueError("Character ID must be numeric when set.")
            # Validate render IDs in case preset is off.
            id_kwargs = self._render_id_kwargs(self.batch_starter_male.get())
            base_id = int(id_kwargs["base_id"])
            if self.batch_all_actions.get():
                actions = detect_actions_for_loadout(
                    base_wz=base_wz,
                    id_kwargs=id_kwargs,
                    mode=self.batch_action_source.get(),
                )
                if not actions:
                    raise ValueError(f"No actions detected for base template {base_id:08d}")
            else:
                action_check = self.batch_action.get().strip()
                if not action_check:
                    raise ValueError("Action is required when all-actions is disabled")
                if self.batch_auto_frames.get():
                    timeline = detect_action_timeline(
                        base_wz,
                        base_id,
                        action_check,
                        default_delay_ms=gif_duration,
                    )
                    if not timeline:
                        raise ValueError(f"No frames detected for action '{action_check}' on base {base_id:08d}")
        except Exception as exc:  # noqa: BLE001
            messagebox.showerror("Validation Error", f"Invalid batch input: {exc}")
            return

        if not self.batch_prefix.get().strip():
            messagebox.showerror("Validation Error", "File prefix is required.")
            return
        if self.coat_id.get().strip() and self.longcoat_id.get().strip():
            self._append_batch_log("Warning: both coat and longcoat are set; layering conflicts may occur.")
        if self.batch_make_gif.get() and not self.batch_all_actions.get() and not self.batch_gif_path.get().strip():
            messagebox.showerror("Validation Error", "GIF path is required when Create GIF is enabled.")
            return
        if self.batch_make_sheet.get() and not self.batch_all_actions.get() and not self.batch_sheet_path.get().strip():
            messagebox.showerror("Validation Error", "Sprite sheet path is required when Create Sprite Sheet is enabled.")
            return

        self.batch_btn.config(state="disabled")
        self._append_batch_log("Starting batch export...")

        def task():
            return run_batch_export(
                base_wz=base_wz,
                base_out_dir=Path(self.batch_output_dir.get()),
                prefix=self.batch_prefix.get().strip(),
                id_kwargs=self._render_id_kwargs(self.batch_starter_male.get()),
                all_actions=bool(self.batch_all_actions.get()),
                action_source=self.batch_action_source.get(),
                single_action=self.batch_action.get().strip(),
                auto_frames=bool(self.batch_auto_frames.get()),
                start_frame=int(self.batch_start.get().strip()),
                end_frame=int(self.batch_end.get().strip()),
                z_draw_order=self.batch_z_draw_order.get(),
                hair_mode=self.batch_hair_mode.get(),
                use_character_folder=bool(self.batch_use_character_folder.get()),
                character_id_raw=self.batch_character_id.get().strip(),
                write_json=bool(self.batch_write_json.get()),
                use_action_delays=bool(self.batch_use_action_delays.get()),
                normalize_canvas=bool(self.batch_normalize_canvas.get()),
                make_gif=bool(self.batch_make_gif.get()),
                gif_path_raw=self.batch_gif_path.get(),
                gif_duration_ms=int(self.batch_gif_duration.get().strip() or "120"),
                make_sheet=bool(self.batch_make_sheet.get()),
                sheet_path_raw=self.batch_sheet_path.get(),
                sheet_cols=int(self.batch_sheet_cols.get().strip() or "8"),
                skip_unresolved=bool(self.batch_skip_unresolved.get()),
                min_layers=int(self.batch_min_layers.get().strip() or "8"),
                skill_id=(
                    int(self.batch_skill_id.get().strip())
                    if self.batch_skill_id.get().strip()
                    else None
                ),
                skill_anim=self.batch_skill_anim.get().strip() or "auto",
                log=lambda msg: self.after(0, lambda m=msg: self._append_batch_log(m)),
            )

        def done(ok: bool, payload) -> None:
            self.batch_btn.config(state="normal")
            if not ok:
                exc, tb = payload
                self._append_batch_log(f"Batch failed: {exc}")
                self._append_batch_log(tb)
                messagebox.showerror("Batch Failed", str(exc))
                return

            summary = payload
            self._append_batch_log("Batch export complete.")
            self._append_batch_log(json.dumps(summary, indent=2))
            first_png: Optional[Path] = None
            for action_row in summary.get("actions", []):
                frames = action_row.get("frames", [])
                if not frames:
                    continue
                candidate = Path(frames[0]["png"])
                if candidate.exists():
                    first_png = candidate
                    break
            if first_png is not None:
                self._update_preview(first_png)

        self._run_async(task, done)

    # ---------------- Catalogue tab ----------------
    def _build_catalogue_tab(self) -> None:
        ttk.Label(
            self.catalogue_tab,
            text="Step 2: Build/load catalogue, search by name, then apply IDs to Render slots.",
        ).pack(anchor="w", padx=8, pady=(8, 0))

        top = ttk.Frame(self.catalogue_tab)
        top.pack(fill="x", padx=8, pady=(4, 8))

        self.cat_base_wz = tk.StringVar(value=DEFAULT_BASE_WZ)
        self.cat_output_dir = tk.StringVar(value=str(Path(DEFAULT_ANALYSIS_DIR) / "catalogue"))
        self.cat_mode = tk.StringVar(value=CATALOGUE_MODE_CHARACTER)
        self.cat_filter_category = tk.StringVar(value="(All)")
        self.cat_search = tk.StringVar(value="")
        self.cat_slot_hint = tk.StringVar(value="Auto slot: (select an item)")
        self.cat_live_action = tk.StringVar(value="stand1")
        self.cat_live_frame = tk.StringVar(value="0")
        self.cat_build_status = tk.StringVar(value="Select a catalogue row to preview. Apply to lock in a build step.")
        self.cat_icon_status = tk.StringVar(value="Selected item icon appears here.")

        self.catalogue_rows: list[dict] = []
        self.catalogue_build_steps: list[dict] = []

        self._build_labeled_entry(top, 0, "Base.wz path", self.cat_base_wz, width=90)
        ttk.Button(top, text="Browse", command=lambda: self._browse_dir(self.cat_base_wz)).grid(
            row=0, column=2, padx=4, pady=4
        )
        self._build_labeled_entry(top, 1, "Catalogue Output Dir", self.cat_output_dir, width=90)
        ttk.Button(top, text="Browse", command=lambda: self._browse_dir(self.cat_output_dir)).grid(
            row=1, column=2, padx=4, pady=4
        )
        ttk.Label(top, text="Catalogue Type").grid(row=2, column=0, sticky="w", padx=4, pady=4)
        self.cat_mode_combo = ttk.Combobox(
            top,
            textvariable=self.cat_mode,
            values=[CATALOGUE_MODE_CHARACTER, CATALOGUE_MODE_ITEMWZ],
            state="readonly",
            width=28,
        )
        self.cat_mode_combo.grid(row=2, column=1, sticky="w", padx=4, pady=4)

        btn_row = ttk.Frame(top)
        btn_row.grid(row=3, column=0, columnspan=3, sticky="w", padx=4, pady=8)
        self.cat_generate_btn = ttk.Button(btn_row, text="Generate Catalogue", command=self.on_generate_catalogue)
        self.cat_generate_btn.pack(side="left", padx=(0, 8))
        ttk.Button(btn_row, text="Load Catalogue", command=self.on_load_catalogue).pack(side="left", padx=(0, 8))
        ttk.Button(btn_row, text="Open Output Folder", command=self.on_open_catalogue_folder).pack(side="left")

        filters = ttk.Frame(top)
        filters.grid(row=4, column=0, columnspan=3, sticky="ew", padx=4, pady=4)
        ttk.Label(filters, text="Category").pack(side="left")
        self.cat_category_combo = ttk.Combobox(
            filters, textvariable=self.cat_filter_category, values=["(All)"], width=20, state="readonly"
        )
        self.cat_category_combo.pack(side="left", padx=(6, 14))
        ttk.Label(filters, text="Search").pack(side="left")
        ttk.Entry(filters, textvariable=self.cat_search, width=40).pack(side="left", padx=(6, 14))
        ttk.Label(filters, text="Apply Slot").pack(side="left")
        ttk.Label(filters, textvariable=self.cat_slot_hint).pack(side="left", padx=(6, 10))
        ttk.Button(filters, text="Apply Selected ID", command=self.on_apply_selected_catalogue_id).pack(side="left")

        content = ttk.Panedwindow(self.catalogue_tab, orient="horizontal")
        content.pack(fill="both", expand=True, padx=8, pady=(0, 8))

        table_wrap = ttk.Frame(content)
        preview_wrap = ttk.LabelFrame(content, text="Piece-by-Piece Build Preview")
        content.add(table_wrap, weight=3)
        content.add(preview_wrap, weight=2)

        cols = ("id", "name", "part_category", "eqp_category", "islot", "vslot")
        self.cat_tree = ttk.Treeview(table_wrap, columns=cols, show="headings", height=22)
        for c, w in (
            ("id", 90),
            ("name", 320),
            ("part_category", 130),
            ("eqp_category", 130),
            ("islot", 70),
            ("vslot", 260),
        ):
            self.cat_tree.heading(c, text=c)
            self.cat_tree.column(c, width=w, anchor="w")
        yscroll = ttk.Scrollbar(table_wrap, orient="vertical", command=self.cat_tree.yview)
        xscroll = ttk.Scrollbar(table_wrap, orient="horizontal", command=self.cat_tree.xview)
        self.cat_tree.configure(yscrollcommand=yscroll.set, xscrollcommand=xscroll.set)
        self.cat_tree.grid(row=0, column=0, sticky="nsew")
        yscroll.grid(row=0, column=1, sticky="ns")
        xscroll.grid(row=1, column=0, sticky="ew")
        table_wrap.rowconfigure(0, weight=1)
        table_wrap.columnconfigure(0, weight=1)
        self.cat_tree.bind("<<TreeviewSelect>>", lambda *_: self.on_catalogue_selection_preview())

        preview_controls = ttk.Frame(preview_wrap)
        preview_controls.pack(fill="x", padx=8, pady=8)
        ttk.Label(preview_controls, text="Action").pack(side="left")
        ttk.Entry(preview_controls, textvariable=self.cat_live_action, width=10).pack(side="left", padx=(6, 10))
        ttk.Label(preview_controls, text="Frame").pack(side="left")
        ttk.Entry(preview_controls, textvariable=self.cat_live_frame, width=6).pack(side="left", padx=(6, 10))
        ttk.Button(preview_controls, text="Refresh", command=self.on_catalogue_selection_preview).pack(
            side="left", padx=(0, 8)
        )
        ttk.Button(preview_controls, text="Reset Steps", command=self.on_reset_build_steps).pack(side="left")

        ttk.Label(preview_wrap, textvariable=self.cat_build_status, wraplength=360).pack(
            anchor="w", padx=8, pady=(0, 8)
        )

        ttk.Label(preview_wrap, text="Selected Item Icon").pack(anchor="w", padx=8)
        self.cat_item_icon_label = ttk.Label(preview_wrap, text="No icon yet.")
        self.cat_item_icon_label.pack(fill="x", expand=False, padx=8, pady=(2, 4))
        ttk.Label(preview_wrap, textvariable=self.cat_icon_status, wraplength=360).pack(
            anchor="w", padx=8, pady=(0, 8)
        )

        self.cat_build_preview_label = ttk.Label(preview_wrap, text="No preview yet.")
        self.cat_build_preview_label.pack(fill="both", expand=False, padx=8, pady=(0, 8))

        ttk.Label(preview_wrap, text="Applied Steps").pack(anchor="w", padx=8)
        steps_wrap = ttk.Frame(preview_wrap)
        steps_wrap.pack(fill="both", expand=True, padx=8, pady=(0, 8))
        self.cat_steps_tree = ttk.Treeview(
            steps_wrap,
            columns=("step", "slot", "id", "name"),
            show="headings",
            height=8,
        )
        for col, w in (("step", 44), ("slot", 110), ("id", 84), ("name", 220)):
            self.cat_steps_tree.heading(col, text=col)
            self.cat_steps_tree.column(col, width=w, anchor="w")
        step_scroll = ttk.Scrollbar(steps_wrap, orient="vertical", command=self.cat_steps_tree.yview)
        self.cat_steps_tree.configure(yscrollcommand=step_scroll.set)
        self.cat_steps_tree.grid(row=0, column=0, sticky="nsew")
        step_scroll.grid(row=0, column=1, sticky="ns")
        steps_wrap.rowconfigure(0, weight=1)
        steps_wrap.columnconfigure(0, weight=1)
        self.cat_steps_tree.bind("<<TreeviewSelect>>", lambda *_: self.on_select_build_step_preview())

        ttk.Label(self.catalogue_tab, text="Catalogue Log").pack(anchor="w", padx=8)
        self.cat_log = tk.Text(self.catalogue_tab, height=8, wrap="word")
        self.cat_log.pack(fill="x", padx=8, pady=(0, 8))

        self.cat_filter_category.trace_add("write", lambda *_: self._refresh_catalogue_tree())
        self.cat_search.trace_add("write", lambda *_: self._refresh_catalogue_tree())
        self.cat_mode.trace_add("write", lambda *_: self._on_catalogue_mode_changed())

    def _append_cat_log(self, text: str) -> None:
        self.cat_log.insert("end", text + "\n")
        self.cat_log.see("end")

    def _is_itemwz_catalogue_mode(self) -> bool:
        return self.cat_mode.get().strip() == CATALOGUE_MODE_ITEMWZ

    def _catalogue_csv_name(self) -> str:
        return "itemwz_catalogue_all.csv" if self._is_itemwz_catalogue_mode() else "catalogue_all.csv"

    def _normalize_catalogue_rows(self, raw_rows: list[dict]) -> list[dict]:
        return normalize_catalogue_rows(raw_rows, itemwz_mode=self._is_itemwz_catalogue_mode())

    def _on_catalogue_mode_changed(self) -> None:
        if self._is_itemwz_catalogue_mode():
            self.cat_slot_hint.set("Auto slot: n/a (Item.wz browse mode)")
        else:
            self.cat_slot_hint.set("Auto slot: (select an item)")

    def on_open_catalogue_folder(self) -> None:
        out = Path(self.cat_output_dir.get())
        out.mkdir(parents=True, exist_ok=True)
        try:
            import os

            os.startfile(str(out))  # type: ignore[attr-defined]
        except Exception as exc:  # noqa: BLE001
            messagebox.showerror("Open Folder Error", str(exc))

    def on_generate_catalogue(self) -> None:
        base_wz = Path(self.cat_base_wz.get())
        base_err = validate_base_wz(base_wz)
        if base_err:
            messagebox.showerror("Validation Error", base_err)
            return

        self.cat_generate_btn.config(state="disabled")
        if self._is_itemwz_catalogue_mode():
            self._append_cat_log("Generating Item.wz catalogue...")
        else:
            self._append_cat_log("Generating character catalogue...")

        def task():
            if self._is_itemwz_catalogue_mode():
                return build_itemwz_catalogue(base_wz=base_wz, output_dir=Path(self.cat_output_dir.get()))
            return build_character_catalogue(base_wz=base_wz, output_dir=Path(self.cat_output_dir.get()))

        def done(ok: bool, payload) -> None:
            self.cat_generate_btn.config(state="normal")
            if not ok:
                exc, tb = payload
                self._append_cat_log(f"Catalogue generation failed: {exc}")
                self._append_cat_log(tb)
                messagebox.showerror("Catalogue Failed", str(exc))
                return
            summary = payload
            total_items = int(summary.get("total_items", 0))
            if self._is_itemwz_catalogue_mode():
                roots = summary.get("roots", {})
                self._append_cat_log(
                    f"Item.wz catalogue complete: {total_items} items across {len(roots)} roots."
                )
            else:
                categories = summary.get("categories", {})
                self._append_cat_log(
                    f"Character catalogue complete: {total_items} items across {len(categories)} categories."
                )
            self.on_load_catalogue()

        self._run_async(task, done)

    def on_load_catalogue(self) -> None:
        all_csv = Path(self.cat_output_dir.get()) / self._catalogue_csv_name()
        if not all_csv.exists():
            messagebox.showerror("Load Error", f"Catalogue not found: {all_csv}")
            return
        with all_csv.open("r", encoding="utf-8", newline="") as f:
            raw_rows = list(csv.DictReader(f))
        self.catalogue_rows = self._normalize_catalogue_rows(raw_rows)

        categories = sorted({r.get("part_category", "") for r in self.catalogue_rows if r.get("part_category", "")})
        self.cat_category_combo["values"] = ["(All)"] + categories
        if self.cat_filter_category.get() not in self.cat_category_combo["values"]:
            self.cat_filter_category.set("(All)")
        self._refresh_catalogue_tree()
        self._update_catalogue_icon_preview(None)
        mode_label = "Item.wz" if self._is_itemwz_catalogue_mode() else "Character"
        self._append_cat_log(f"Loaded {mode_label} catalogue rows: {len(self.catalogue_rows)} ({all_csv.name})")

    def _refresh_catalogue_tree(self) -> None:
        if not hasattr(self, "cat_tree"):
            return
        for item in self.cat_tree.get_children():
            self.cat_tree.delete(item)
        self._cat_tree_row_lookup = {}

        cat_filter = self.cat_filter_category.get()
        q = self.cat_search.get().strip().lower()
        shown = 0
        for r in self.catalogue_rows:
            if cat_filter != "(All)" and r.get("part_category", "") != cat_filter:
                continue
            hay = " ".join(
                [
                    r.get("id", ""),
                    r.get("name", ""),
                    r.get("part_category", ""),
                    r.get("eqp_category", ""),
                    r.get("islot", ""),
                    r.get("vslot", ""),
                ]
            ).lower()
            if q and q not in hay:
                continue
            row_id = self.cat_tree.insert(
                "",
                "end",
                values=(
                    r.get("id", ""),
                    r.get("name", ""),
                    r.get("part_category", ""),
                    r.get("eqp_category", ""),
                    r.get("islot", ""),
                    r.get("vslot", ""),
                ),
            )
            self._cat_tree_row_lookup[row_id] = r
            shown += 1
            if shown >= 5000:
                break

    def _slot_var_map(self) -> dict[str, tk.StringVar]:
        return {
            "face_id": self.face_id,
            "hair_id": self.hair_id,
            "accessory_id": self.accessory_id,
            "cap_id": self.cap_id,
            "coat_id": self.coat_id,
            "longcoat_id": self.longcoat_id,
            "pants_id": self.pants_id,
            "shoes_id": self.shoes_id,
            "glove_id": self.glove_id,
            "cape_id": self.cape_id,
            "shield_id": self.shield_id,
            "weapon_id": self.weapon_id,
        }

    def _ensure_catalogue_rows_loaded(self) -> None:
        if getattr(self, "catalogue_rows", None):
            if self.catalogue_rows:
                return
        out_dir = Path(self.cat_output_dir.get()) if hasattr(self, "cat_output_dir") else (Path(DEFAULT_ANALYSIS_DIR) / "catalogue")
        all_csv = out_dir / self._catalogue_csv_name()
        if not all_csv.exists():
            return
        try:
            with all_csv.open("r", encoding="utf-8", newline="") as f:
                raw_rows = list(csv.DictReader(f))
                self.catalogue_rows = self._normalize_catalogue_rows(raw_rows)
        except Exception:
            return

    def _get_body_id_pools(self, base_wz: Path) -> dict[str, list[int]]:
        cache_key = str(base_wz)
        if getattr(self, "_body_pool_cache_key", None) == cache_key:
            cached = getattr(self, "_body_pool_cache", None)
            if isinstance(cached, dict):
                return cached

        pools = get_body_id_pools(base_wz)
        self._body_pool_cache_key = cache_key
        self._body_pool_cache = pools
        return pools

    def _random_catalogue_id_for_slot(self, slot_name: str) -> Optional[str]:
        self._ensure_catalogue_rows_loaded()
        rows = getattr(self, "catalogue_rows", [])
        candidates: list[int] = []
        for row in rows:
            item_id = str(row.get("id", "")).strip()
            if not item_id.isdigit():
                continue
            inferred = infer_slot_from_catalogue_categories(
                str(row.get("part_category", "")),
                str(row.get("eqp_category", "")),
            )
            if inferred == slot_name:
                candidates.append(int(item_id))
        if not candidates:
            return None
        return str(random.choice(candidates))

    def _random_value_for_slot(self, slot_name: str) -> Optional[str]:
        if slot_name in ("base_id", "head_id"):
            base_wz = Path(self.render_base_wz.get().strip())
            err = validate_base_wz(base_wz)
            if err:
                return None
            pools = self._get_body_id_pools(base_wz)
            vals = pools.get(slot_name, [])
            if not vals:
                return None
            return str(random.choice(vals))
        return self._random_catalogue_id_for_slot(slot_name)

    def _set_slot_value(self, slot_name: str, value: str) -> None:
        if slot_name == "base_id":
            self.base_id.set(value)
            return
        if slot_name == "head_id":
            self.head_id.set(value)
            return

        slot_vars = self._slot_var_map()
        var = slot_vars.get(slot_name)
        if var is None:
            return
        var.set(value)
        if slot_name == "coat_id" and value.strip():
            self.longcoat_id.set("")
        elif slot_name == "longcoat_id" and value.strip():
            self.coat_id.set("")

    def on_randomize_slot(self, slot_name: str) -> None:
        picked = self._random_value_for_slot(slot_name)
        if picked is None:
            self._append_render_log(f"Randomize skipped for {slot_name}: no candidate IDs found.")
            return
        self._set_slot_value(slot_name, picked)
        self._append_render_log(f"Randomized {slot_name} -> {picked}")

    def on_randomize_all_slots(self) -> None:
        changed = 0
        skipped = 0

        for slot_name in (
            "base_id",
            "head_id",
            "face_id",
            "hair_id",
            "accessory_id",
            "cap_id",
            "pants_id",
            "shoes_id",
            "glove_id",
            "cape_id",
            "shield_id",
            "weapon_id",
        ):
            picked = self._random_value_for_slot(slot_name)
            if picked is None:
                skipped += 1
                continue
            self._set_slot_value(slot_name, picked)
            changed += 1

        coat_val = self._random_value_for_slot("coat_id")
        longcoat_val = self._random_value_for_slot("longcoat_id")
        coat_choices = []
        if coat_val is not None:
            coat_choices.append(("coat_id", coat_val))
        if longcoat_val is not None:
            coat_choices.append(("longcoat_id", longcoat_val))
        if coat_choices:
            chosen_slot, chosen_val = random.choice(coat_choices)
            self._set_slot_value(chosen_slot, chosen_val)
            changed += 1
        else:
            skipped += 1

        self._append_render_log(f"Randomized all slots: changed={changed}, skipped={skipped}")

    def _infer_slot_from_catalogue_categories(
        self,
        part_category: str,
        eqp_category: str,
    ) -> Optional[str]:
        aliases = {
            "face": "face_id",
            "hair": "hair_id",
            "accessory": "accessory_id",
            "cap": "cap_id",
            "coat": "coat_id",
            "longcoat": "longcoat_id",
            "pants": "pants_id",
            "shoes": "shoes_id",
            "glove": "glove_id",
            "cape": "cape_id",
            "shield": "shield_id",
            "weapon": "weapon_id",
        }
        for raw in (part_category, eqp_category):
            key = (raw or "").strip().lower().replace("_", "").replace(" ", "")
            if key in aliases:
                return aliases[key]
        return None

    def _selected_catalogue_item(self) -> Optional[dict]:
        sel = self.cat_tree.selection()
        if not sel:
            return None
        tree_row = self._cat_tree_row_lookup.get(sel[0])
        if tree_row is not None:
            return dict(tree_row)
        values = self.cat_tree.item(sel[0], "values")
        if not values or not str(values[0]).isdigit():
            return None
        return {
            "id": str(values[0]),
            "name": str(values[1]) if len(values) > 1 else "",
            "part_category": str(values[2]) if len(values) > 2 else "",
            "eqp_category": str(values[3]) if len(values) > 3 else "",
        }

    def _resolve_catalogue_icon_path(self, item: dict) -> Optional[Path]:
        return resolve_catalogue_icon_path(Path((self.cat_base_wz.get() or "").strip()), item)

    def _update_catalogue_icon_preview(self, item: Optional[dict]) -> None:
        if not hasattr(self, "cat_item_icon_label"):
            return
        if item is None:
            self.cat_item_icon_label.config(image="", text="No icon yet.")
            self.catalogue_item_icon_image = None
            self.cat_icon_status.set("Selected item icon appears here.")
            return

        icon_path = self._resolve_catalogue_icon_path(item)
        item_name = str(item.get("name", "")).strip() or "(unnamed)"
        item_id = str(item.get("id", "")).strip() or "?"
        if icon_path is None:
            self.cat_item_icon_label.config(image="", text="Icon not found.")
            self.catalogue_item_icon_image = None
            self.cat_icon_status.set(f"{item_name} [{item_id}]")
            return
        try:
            pil = Image.open(icon_path).convert("RGBA")
            pil.thumbnail((96, 96), Image.Resampling.NEAREST)
            self.catalogue_item_icon_image = ImageTk.PhotoImage(pil)
            self.cat_item_icon_label.config(image=self.catalogue_item_icon_image, text="")
            self.cat_icon_status.set(f"{item_name} [{item_id}]")
        except Exception as exc:  # noqa: BLE001
            self.cat_item_icon_label.config(image="", text="Icon load failed.")
            self.catalogue_item_icon_image = None
            self.cat_icon_status.set(f"{item_name} [{item_id}] icon error: {exc}")

    def _render_catalogue_build_preview(
        self,
        output_name: str,
        status_text: str,
    ) -> Optional[Path]:
        base_wz = Path(self.cat_base_wz.get().strip())
        err = validate_base_wz(base_wz)
        if err:
            self.cat_build_status.set(f"Preview blocked: {err}")
            return None

        try:
            frame = int((self.cat_live_frame.get() or "0").strip())
            if frame < 0:
                raise ValueError("frame must be >= 0")
        except Exception:
            self.cat_build_status.set("Preview blocked: frame must be a non-negative integer.")
            return None

        action = (self.cat_live_action.get() or "stand1").strip()
        if not action:
            action = "stand1"

        out_dir = Path(DEFAULT_ANALYSIS_DIR) / "build_preview"
        out_dir.mkdir(parents=True, exist_ok=True)
        png_path = out_dir / output_name
        try:
            kwargs = self._render_id_kwargs(self.render_starter_male.get())
            render(
                base_wz=base_wz,
                output_png=png_path,
                action=action,
                frame=frame,
                output_json=None,
                z_draw_order=self.render_z_draw_order.get(),
                hair_mode=self.render_hair_mode.get(),
                **kwargs,
            )
            self._update_preview(
                png_path,
                target_label=self.cat_build_preview_label,
                max_size=(360, 360),
                cache_attr="catalogue_build_preview_image",
            )
            self.cat_build_status.set(status_text)
            return png_path
        except Exception as exc:  # noqa: BLE001
            self.cat_build_status.set(f"Preview failed: {exc}")
            return None

    def on_catalogue_selection_preview(self) -> None:
        item = self._selected_catalogue_item()
        if item is None:
            self.cat_slot_hint.set("Auto slot: (select an item)")
            self._update_catalogue_icon_preview(None)
            return
        self._update_catalogue_icon_preview(item)
        item_id = item["id"]
        item_name = item["name"]
        if self._is_itemwz_catalogue_mode():
            self.cat_slot_hint.set("Auto slot: n/a (Item.wz)")
            self.cat_build_status.set(
                f"Item.wz selection: {item_name} [{item_id}] (browse-only in this build)."
            )
            return
        target = infer_slot_from_catalogue_categories(item["part_category"], item["eqp_category"])
        if target is None:
            self.cat_slot_hint.set("Auto slot: unsupported")
            self.cat_build_status.set(
                f"No renderer slot mapping for category '{item['part_category']}' ({item_name} [{item_id}])."
            )
            return
        self.cat_slot_hint.set(f"Auto slot: {target}")
        slot_vars = self._slot_var_map()
        target_var = slot_vars.get(target)
        if target_var is None:
            return

        old_value = target_var.get()
        try:
            target_var.set(item_id)
            self._render_catalogue_build_preview(
                output_name="catalogue_candidate_preview.png",
                status_text=f"Previewing candidate: auto {target} = {item_name} [{item_id}]",
            )
        finally:
            target_var.set(old_value)

    def on_reset_build_steps(self) -> None:
        self.catalogue_build_steps = []
        for item in self.cat_steps_tree.get_children():
            self.cat_steps_tree.delete(item)
        self.cat_build_preview_label.config(image="", text="No preview yet.")
        self.cat_build_status.set("Build steps reset.")
        self._append_cat_log("Reset piece-by-piece build history.")

    def _record_catalogue_build_step(self, slot: str, item_id: str, item_name: str) -> None:
        step_num = len(self.catalogue_build_steps) + 1
        png_path = self._render_catalogue_build_preview(
            output_name=f"catalogue_build_step_{step_num:03d}.png",
            status_text=f"Build step {step_num}: applied {slot} = {item_name} [{item_id}]",
        )
        step = {
            "step": step_num,
            "slot": slot,
            "id": item_id,
            "name": item_name,
            "png": str(png_path) if png_path is not None else "",
        }
        self.catalogue_build_steps.append(step)
        self.cat_steps_tree.insert(
            "",
            "end",
            values=(step["step"], step["slot"], step["id"], step["name"]),
        )

    def on_select_build_step_preview(self) -> None:
        sel = self.cat_steps_tree.selection()
        if not sel:
            return
        values = self.cat_steps_tree.item(sel[0], "values")
        if not values:
            return
        try:
            step_num = int(values[0])
        except Exception:
            return
        match = next((s for s in self.catalogue_build_steps if int(s["step"]) == step_num), None)
        if match is None:
            return
        png_raw = str(match.get("png", "")).strip()
        if not png_raw:
            self.cat_build_status.set(f"Step {step_num} has no preview image.")
            return
        png = Path(png_raw)
        self._update_preview(
            png,
            target_label=self.cat_build_preview_label,
            max_size=(360, 360),
            cache_attr="catalogue_build_preview_image",
        )
        self.cat_build_status.set(
            f"Showing step {step_num}: {match['slot']} = {match['name']} [{match['id']}]"
        )

    def on_apply_selected_catalogue_id(self) -> None:
        item = self._selected_catalogue_item()
        if item is None:
            messagebox.showerror("Apply Error", "Select a catalogue row first.")
            return
        if self._is_itemwz_catalogue_mode():
            messagebox.showinfo(
                "Browse-Only",
                (
                    "Item.wz catalogue entries are browse-only right now.\n"
                    "Switch Catalogue Type to 'Character (Equip)' to apply IDs to render slots."
                ),
            )
            return
        item_id = item["id"]
        item_name = item["name"]
        target = infer_slot_from_catalogue_categories(item["part_category"], item["eqp_category"])
        if target is None:
            messagebox.showerror(
                "Apply Error",
                (
                    "This item category is not mapped to a renderer slot yet.\n"
                    f"Category: {item['part_category']}\nItem: {item_name} [{item_id}]"
                ),
            )
            return
        slot_vars = self._slot_var_map()
        if target not in slot_vars:
            messagebox.showerror("Apply Error", f"Unknown target slot: {target}")
            return
        slot_vars[target].set(item_id)
        self._append_cat_log(f"Applied ID {item_id} to {target}")
        self.cat_slot_hint.set(f"Auto slot: {target}")
        self._record_catalogue_build_step(target, item_id, item_name)
        messagebox.showinfo("Applied", f"Set {target} = {item_id}")


def main() -> None:
    global DEFAULT_BASE_WZ, DEFAULT_ANALYSIS_DIR

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--base-wz",
        default=None,
        help=(
            "Initial Base.wz path pre-filled in the GUI. Falls back to the "
            f"{BASE_WZ_ENV_VAR} environment variable, then to the "
            "maintainer's local default if neither is set."
        ),
    )
    parser.add_argument(
        "--analysis-dir",
        default=None,
        help=(
            "Initial analysis output directory pre-filled in the GUI. Falls "
            f"back to the {ANALYSIS_DIR_ENV_VAR} environment variable, then "
            "to the maintainer's local default if neither is set."
        ),
    )
    args = parser.parse_args()
    DEFAULT_BASE_WZ = resolve_default_path(args.base_wz, BASE_WZ_ENV_VAR, FALLBACK_BASE_WZ)
    DEFAULT_ANALYSIS_DIR = resolve_default_path(
        args.analysis_dir, ANALYSIS_DIR_ENV_VAR, FALLBACK_ANALYSIS_DIR
    )

    app = App()
    app.mainloop()


if __name__ == "__main__":
    main()
