#!/usr/bin/python3
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "Resources" / "Scripts" / "excel_sync.py"
PYTHONPATH = ROOT / "Resources" / "python"

sys.path.insert(0, str(PYTHONPATH))
from openpyxl import Workbook, load_workbook  # noqa: E402


def run(command, workbook, payload):
    env = os.environ.copy()
    env["PYTHONPATH"] = str(PYTHONPATH)
    result = subprocess.run(
        [sys.executable, str(SCRIPT), command, str(workbook)],
        input=json.dumps(payload),
        text=True,
        capture_output=True,
        env=env,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr or result.stdout)
    decoded = json.loads(result.stdout)
    if not decoded.get("success"):
        raise RuntimeError(decoded.get("error") or result.stdout)
    return decoded


def make_workbook(path):
    wb = Workbook()
    ws = wb.active
    ws.title = "Inventory"
    ws.append(["Item Type", "Description", "Manufacturer", "Part Number", "Purchase Date", "Vendor", "Unit Cost", "Quantity", "Total Cost", "Qty Received", "PO Number", "Remaining Inventory", "Notes"])
    ws.append(["Laptop", "Example Laptop", "Example Manufacturer", "LAP-1", "2026-01-01", "Example Vendor", 1000, 5, "=G2*H2", "5/5", "PO-1", 5, "Seed"])
    ws2 = wb.create_sheet("OpEx")
    ws2.append(["Item Type", "Description", "Manufacturer", "Part Number", "Purchase Date", "Vendor", "Unit Cost", "Quantity", "Total Cost", "Qty Received", "PO Number", "Remaining Inventory", "Notes"])
    ws3 = wb.create_sheet("Items Deployed")
    ws3.append(["Item Type", "Description", "Manufacturer", "Part Number", "Qty Deployed", "Deployed To", "Deployed By", "Deployed Date", "Location", "Notes"])
    wb.save(path)


def main():
    tmp = Path(tempfile.mkdtemp(prefix="inventory-import-fixture-"))
    try:
        workbook = tmp / "fixture.xlsx"
        make_workbook(workbook)
        run("append-inventory", workbook, {"items": [{
            "itemType": "Peripheral",
            "description": "Example Dock",
            "manufacturer": "Example Manufacturer",
            "partNumber": "DOCK-1",
            "purchaseDate": "2026-02-01",
            "vendor": "Example Vendor",
            "unitCost": 199,
            "quantity": 3,
            "qtyReceived": 3,
            "poNumber": "PO-2",
            "budgetType": "OpEx",
            "stockroomName": "Main",
            "notes": "Fixture"
        }]})
        run("append-deployed", workbook, {"deployments": [{
            "itemType": "Laptop",
            "description": "Example Laptop",
            "manufacturer": "Example Manufacturer",
            "partNumber": "LAP-1",
            "qtyDeployed": 2,
            "deployedTo": "Example Team",
            "deployedBy": "Smoke Test",
            "deployedDate": "2026-03-01",
            "deployedLocation": "HQ",
            "notes": "Fixture deployment"
        }, {
            "itemType": "Peripheral",
            "description": "Example Dock",
            "manufacturer": "Example Manufacturer",
            "partNumber": "DOCK-1",
            "qtyDeployed": 1,
            "deployedTo": "Example Desk",
            "deployedBy": "Smoke Test",
            "deployedDate": "2026-03-02",
            "deployedLocation": "HQ",
            "notes": "Linked fixture deployment"
        }]})
        run("update-remaining", workbook, {"items": [{
            "partNumber": "LAP-1",
            "poNumber": "PO-1",
            "budgetType": "Capital",
            "remaining": 3
        }]})
        remaining_value = load_workbook(workbook)["Inventory"].cell(row=2, column=12).value
        if remaining_value != 3:
            raise AssertionError(f"update-remaining left remaining inventory at {remaining_value!r}")
        inventory = run("read-inventory", workbook, {})
        deployed = run("read-deployed", workbook, {})
        if len(inventory.get("items", [])) < 2 or len(deployed.get("deployments", [])) < 1:
            raise AssertionError("fixture workbook did not round-trip expected rows")
        run("delete-deployed", workbook, {"deployments": [{
            "itemType": "Laptop",
            "description": "Example Laptop",
            "manufacturer": "Example Manufacturer",
            "partNumber": "LAP-1",
            "qtyDeployed": 2,
            "deployedTo": "Example Team",
            "deployedBy": "Smoke Test",
            "deployedDate": "2026-03-01",
            "deployedLocation": "HQ",
            "notes": "Fixture deployment"
        }]})
        run("delete-inventory", workbook, {"items": [{
            "itemType": "Peripheral",
            "description": "Example Dock",
            "manufacturer": "Example Manufacturer",
            "partNumber": "DOCK-1",
            "purchaseDate": "2026-02-01",
            "vendor": "Example Vendor",
            "unitCost": 199,
            "quantity": 3,
            "qtyReceived": 3,
            "poNumber": "PO-2",
            "budgetType": "OpEx",
            "notes": "Fixture"
        }], "deployments": [{
            "itemType": "Peripheral",
            "description": "Example Dock",
            "manufacturer": "Example Manufacturer",
            "partNumber": "DOCK-1",
            "qtyDeployed": 1,
            "deployedTo": "Example Desk",
            "deployedBy": "Smoke Test",
            "deployedDate": "2026-03-02",
            "deployedLocation": "HQ",
            "notes": "Linked fixture deployment"
        }]})
        inventory_after_delete = run("read-inventory", workbook, {})
        deployed_after_delete = run("read-deployed", workbook, {})
        if any(item.get("partNumber") == "DOCK-1" for item in inventory_after_delete.get("items", [])):
            raise AssertionError("delete-inventory did not remove the matching workbook row")
        if deployed_after_delete.get("deployments", []):
            raise AssertionError("delete-deployed did not remove the matching workbook row")
        print("import_fixture_smoke=ok")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
