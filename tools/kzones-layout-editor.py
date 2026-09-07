#!/usr/bin/env python3
"""A visual editor for KZones layouts stored in ~/.config/kwinrc."""

import json
import subprocess
import sys

from PyQt6.QtCore import QPointF, QRectF, Qt, pyqtSignal
from PyQt6.QtGui import QAction, QColor, QPainter, QPen
from PyQt6.QtWidgets import (
    QApplication, QComboBox, QDialog, QDialogButtonBox, QFormLayout,
    QCheckBox, QHBoxLayout, QLabel, QLineEdit, QListWidget, QMainWindow, QMessageBox,
    QPushButton, QSpinBox, QSplitter, QVBoxLayout, QWidget,
)


DEFAULT_LAYOUTS = [
    {"name": "Priority Grid", "padding": 0, "zones": [
        {"x": 0, "y": 0, "width": 25, "height": 100},
        {"x": 25, "y": 0, "width": 50, "height": 100},
        {"x": 75, "y": 0, "width": 25, "height": 100},
    ]},
    {"name": "Quadrant Grid", "padding": 0, "zones": [
        {"x": 0, "y": 0, "width": 50, "height": 50},
        {"x": 50, "y": 0, "width": 50, "height": 50},
        {"x": 0, "y": 50, "width": 50, "height": 50},
        {"x": 50, "y": 50, "width": 50, "height": 50},
    ]},
]


def read_layouts():
    result = subprocess.run(
        ["kreadconfig6", "--file", "kwinrc", "--group", "Script-kzones", "--key", "layoutsJson"],
        text=True, capture_output=True, check=False,
    )
    if result.returncode or not result.stdout.strip():
        return json.loads(json.dumps(DEFAULT_LAYOUTS))
    try:
        layouts = json.loads(result.stdout)
        if not isinstance(layouts, list) or not layouts:
            raise ValueError("expected a non-empty array")
        return layouts
    except (ValueError, json.JSONDecodeError):
        return json.loads(json.dumps(DEFAULT_LAYOUTS))


class LayoutCanvas(QWidget):
    changed = pyqtSignal()
    selectionChanged = pyqtSignal(int)
    dividerRequested = pyqtSignal(str, int)

    RULER_SIZE = 20
    HANDLE_SIZE = 8
    MIN_ZONE_SIZE = 2

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setMinimumSize(520, 360)
        self.setMouseTracking(True)
        self.zones = []
        self.selected = -1
        self.origin = QPointF()
        self.scale = 1.0
        self.drawing_start = None
        self.drawing_current = None
        self.drag_start = None
        self.drag_zone = None
        self.interaction = None
        self.resize_edges = set()
        self.floating = False

    def set_zones(self, zones):
        self.zones = zones
        self.selected = -1
        self.update()

    def set_floating(self, floating):
        self.floating = floating
        self.update()

    def editor_rect(self):
        margin = 26
        width = max(1, self.width() - margin * 2)
        height = max(1, self.height() - margin * 2)
        side = min(width, height * 16 / 9)
        h = side * 9 / 16
        return QRectF((self.width() - side) / 2, (self.height() - h) / 2, side, h)

    def percent_point(self, point):
        rect = self.editor_rect()
        x = max(0, min(100, round((point.x() - rect.x()) * 100 / rect.width())))
        y = max(0, min(100, round((point.y() - rect.y()) * 100 / rect.height())))
        return QPointF(x, y)

    def snap_coordinate(self, value, axis, ignored_index=-1):
        """Snap a coordinate to the grid or a nearby zone edge in sticky mode."""
        if self.floating:
            return round(value)
        candidates = list(range(0, 101, 5))
        for index, zone in enumerate(self.zones):
            if index == ignored_index:
                continue
            candidates.extend((zone[axis], zone[axis] + zone["width" if axis == "x" else "height"]))
        closest = min(candidates, key=lambda candidate: abs(candidate - value))
        return closest if abs(closest - value) <= 3 else round(value)

    def snap_point(self, point):
        return QPointF(
            self.snap_coordinate(point.x(), "x"),
            self.snap_coordinate(point.y(), "y"),
        )

    def zone_rect(self, zone):
        rect = self.editor_rect()
        return QRectF(
            rect.x() + rect.width() * zone["x"] / 100,
            rect.y() + rect.height() * zone["y"] / 100,
            rect.width() * zone["width"] / 100,
            rect.height() * zone["height"] / 100,
        )

    def resize_edges_at(self, point, zone):
        rect = self.zone_rect(zone)
        tolerance = self.HANDLE_SIZE
        edges = set()
        if abs(point.x() - rect.left()) <= tolerance:
            edges.add("left")
        if abs(point.x() - rect.right()) <= tolerance:
            edges.add("right")
        if abs(point.y() - rect.top()) <= tolerance:
            edges.add("top")
        if abs(point.y() - rect.bottom()) <= tolerance:
            edges.add("bottom")
        return edges

    def cursor_for_edges(self, edges):
        if ("left" in edges or "right" in edges) and ("top" in edges or "bottom" in edges):
            if ("left" in edges and "top" in edges) or ("right" in edges and "bottom" in edges):
                return Qt.CursorShape.SizeFDiagCursor
            return Qt.CursorShape.SizeBDiagCursor
        if "left" in edges or "right" in edges:
            return Qt.CursorShape.SizeHorCursor
        return Qt.CursorShape.SizeVerCursor

    def clamp_geometry(self, zone):
        zone["x"] = max(0, min(100 - self.MIN_ZONE_SIZE, round(zone["x"])))
        zone["y"] = max(0, min(100 - self.MIN_ZONE_SIZE, round(zone["y"])))
        zone["width"] = max(self.MIN_ZONE_SIZE, min(100 - zone["x"], round(zone["width"])))
        zone["height"] = max(self.MIN_ZONE_SIZE, min(100 - zone["y"], round(zone["height"])))

    @staticmethod
    def overlap_on_axis(first_start, first_size, second_start, second_size):
        return min(first_start + first_size, second_start + second_size) - max(first_start, second_start) >= LayoutCanvas.MIN_ZONE_SIZE

    def propagate_sticky_resize(self, original, resized):
        """Keep shared edges connected when a sticky zone is resized.

        A small tolerance also repairs layouts created before the editor which
        have a few percent of overlap between neighbouring zones.
        """
        if self.floating:
            return
        tolerance = 6
        original_right = original["x"] + original["width"]
        original_bottom = original["y"] + original["height"]
        resized_right = resized["x"] + resized["width"]
        resized_bottom = resized["y"] + resized["height"]

        for index, other in enumerate(self.zones):
            if index == self.selected:
                continue
            overlaps_y = self.overlap_on_axis(original["y"], original["height"], other["y"], other["height"])
            overlaps_x = self.overlap_on_axis(original["x"], original["width"], other["x"], other["width"])
            other_right = other["x"] + other["width"]
            other_bottom = other["y"] + other["height"]

            # Right edge moved: move the left edge of the neighbouring zone,
            # preserving its far/right edge.
            if "right" in self.resize_edges and overlaps_y and original["x"] + self.MIN_ZONE_SIZE <= other["x"] <= original_right + tolerance:
                if other_right - resized_right >= self.MIN_ZONE_SIZE:
                    other["x"] = resized_right
                    other["width"] = other_right - resized_right

            # Left edge moved: move the right edge of the neighbouring zone.
            if "left" in self.resize_edges and overlaps_y and original["x"] - tolerance <= other_right <= original_right - self.MIN_ZONE_SIZE:
                if resized["x"] - other["x"] >= self.MIN_ZONE_SIZE:
                    other["width"] = resized["x"] - other["x"]

            # Bottom edge moved: move the top edge of the zone below.
            if "bottom" in self.resize_edges and overlaps_x and original["y"] + self.MIN_ZONE_SIZE <= other["y"] <= original_bottom + tolerance:
                if other_bottom - resized_bottom >= self.MIN_ZONE_SIZE:
                    other["y"] = resized_bottom
                    other["height"] = other_bottom - resized_bottom

            # Top edge moved: move the bottom edge of the zone above.
            if "top" in self.resize_edges and overlaps_x and original["y"] - tolerance <= other_bottom <= original_bottom - self.MIN_ZONE_SIZE:
                if resized["y"] - other["y"] >= self.MIN_ZONE_SIZE:
                    other["height"] = resized["y"] - other["y"]

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)
        rect = self.editor_rect()
        painter.fillRect(self.rect(), self.palette().window())
        painter.fillRect(rect, QColor("#20252b"))
        top_ruler = QRectF(rect.left(), rect.top() - self.RULER_SIZE, rect.width(), self.RULER_SIZE)
        left_ruler = QRectF(rect.left() - self.RULER_SIZE, rect.top(), self.RULER_SIZE, rect.height())
        painter.fillRect(top_ruler, QColor("#303840"))
        painter.fillRect(left_ruler, QColor("#303840"))
        painter.setPen(QPen(QColor("#59636e"), 1))
        for step in range(0, 101, 10):
            x = rect.x() + rect.width() * step / 100
            y = rect.y() + rect.height() * step / 100
            painter.drawLine(QPointF(x, rect.top()), QPointF(x, rect.bottom()))
            painter.drawLine(QPointF(rect.left(), y), QPointF(rect.right(), y))
            painter.drawLine(QPointF(x, top_ruler.top()), QPointF(x, top_ruler.bottom()))
            painter.drawLine(QPointF(left_ruler.left(), y), QPointF(left_ruler.right(), y))
        painter.setPen(QColor("#b7c7d6"))
        painter.drawText(top_ruler, Qt.AlignmentFlag.AlignCenter, "click to split vertically")
        painter.save()
        painter.translate(left_ruler.center())
        painter.rotate(-90)
        painter.drawText(QRectF(-left_ruler.height() / 2, -left_ruler.width() / 2, left_ruler.height(), left_ruler.width()), Qt.AlignmentFlag.AlignCenter, "click to split horizontally")
        painter.restore()
        draw_order = [index for index in range(len(self.zones)) if index != self.selected]
        if 0 <= self.selected < len(self.zones):
            draw_order.append(self.selected)
        for index in draw_order:
            zone = self.zones[index]
            zone_rect = self.zone_rect(zone).adjusted(2, 2, -2, -2)
            active = index == self.selected
            painter.fillRect(zone_rect, QColor("#3daee9" if active else "#356d91"))
            painter.setPen(QPen(QColor("#d8f0ff" if active else "#8fc8ef"), 3 if active else 1))
            painter.drawRect(zone_rect)
            painter.setPen(self.palette().text().color())
            painter.drawText(zone_rect, Qt.AlignmentFlag.AlignCenter, str(index + 1))
            if active:
                painter.setBrush(QColor("#d8f0ff"))
                painter.setPen(QPen(QColor("#1c6b94"), 1))
                for x in (zone_rect.left(), zone_rect.center().x(), zone_rect.right()):
                    for y in (zone_rect.top(), zone_rect.center().y(), zone_rect.bottom()):
                        if x == zone_rect.center().x() and y == zone_rect.center().y():
                            continue
                        painter.drawRect(QRectF(x - self.HANDLE_SIZE / 2, y - self.HANDLE_SIZE / 2, self.HANDLE_SIZE, self.HANDLE_SIZE))
        if self.drawing_start is not None:
            x1, y1 = self.drawing_start.x(), self.drawing_start.y()
            x2, y2 = self.drawing_current.x(), self.drawing_current.y()
            preview = {"x": min(x1, x2), "y": min(y1, y2), "width": abs(x2 - x1), "height": abs(y2 - y1)}
            painter.setPen(QPen(QColor("#fdbc4b"), 2, Qt.PenStyle.DashLine))
            painter.drawRect(self.zone_rect(preview))

    def mousePressEvent(self, event):
        if event.button() != Qt.MouseButton.LeftButton:
            return
        point = event.position()
        rect = self.editor_rect()
        if rect.left() <= point.x() <= rect.right() and rect.top() - self.RULER_SIZE <= point.y() < rect.top():
            self.dividerRequested.emit("vertical", round(self.percent_point(point).x()))
            return
        if rect.left() - self.RULER_SIZE <= point.x() < rect.left() and rect.top() <= point.y() <= rect.bottom():
            self.dividerRequested.emit("horizontal", round(self.percent_point(point).y()))
            return
        # A selected zone stays resizable even when an old layout has an
        # overlap and a later zone is painted over its edge.
        if 0 <= self.selected < len(self.zones):
            edges = self.resize_edges_at(point, self.zones[self.selected])
            if edges:
                self.drag_start = self.percent_point(point)
                self.drag_zone = dict(self.zones[self.selected])
                self.resize_edges = edges
                self.interaction = "resize"
                self.selectionChanged.emit(self.selected)
                self.update()
                return
        for index in range(len(self.zones) - 1, -1, -1):
            if self.zone_rect(self.zones[index]).contains(point):
                self.selected = index
                self.drag_start = self.percent_point(point)
                self.drag_zone = dict(self.zones[index])
                self.resize_edges = self.resize_edges_at(point, self.zones[index])
                self.interaction = "resize" if self.resize_edges else "move"
                self.selectionChanged.emit(index)
                self.update()
                return
        self.selected = -1
        self.selectionChanged.emit(-1)
        self.drawing_start = self.snap_point(self.percent_point(point))
        self.drawing_current = self.drawing_start
        self.update()

    def mouseMoveEvent(self, event):
        point = self.snap_point(self.percent_point(event.position()))
        if self.drawing_start is not None:
            self.drawing_current = point
            self.update()
        elif self.drag_start is not None:
            dx, dy = point.x() - self.drag_start.x(), point.y() - self.drag_start.y()
            zone = self.zones[self.selected]
            if self.interaction == "move":
                x = self.snap_coordinate(self.drag_zone["x"] + dx, "x", self.selected)
                y = self.snap_coordinate(self.drag_zone["y"] + dy, "y", self.selected)
                zone["x"] = max(0, min(100 - self.drag_zone["width"], x))
                zone["y"] = max(0, min(100 - self.drag_zone["height"], y))
            else:
                zone.update(self.drag_zone)
                right = self.drag_zone["x"] + self.drag_zone["width"]
                bottom = self.drag_zone["y"] + self.drag_zone["height"]
                if "left" in self.resize_edges:
                    left = min(right - self.MIN_ZONE_SIZE, self.snap_coordinate(point.x(), "x", self.selected))
                    zone["x"] = max(0, left)
                    zone["width"] = right - zone["x"]
                if "right" in self.resize_edges:
                    zone["width"] = max(self.MIN_ZONE_SIZE, self.snap_coordinate(point.x(), "x", self.selected) - zone["x"])
                if "top" in self.resize_edges:
                    top = min(bottom - self.MIN_ZONE_SIZE, self.snap_coordinate(point.y(), "y", self.selected))
                    zone["y"] = max(0, top)
                    zone["height"] = bottom - zone["y"]
                if "bottom" in self.resize_edges:
                    zone["height"] = max(self.MIN_ZONE_SIZE, self.snap_coordinate(point.y(), "y", self.selected) - zone["y"])
                self.clamp_geometry(zone)
                self.propagate_sticky_resize(self.drag_zone, zone)
            self.changed.emit()
            self.update()
        else:
            self.update_hover_cursor(event.position())

    def update_hover_cursor(self, point):
        rect = self.editor_rect()
        if rect.left() <= point.x() <= rect.right() and rect.top() - self.RULER_SIZE <= point.y() < rect.top():
            self.setCursor(Qt.CursorShape.SplitHCursor)
            return
        if rect.left() - self.RULER_SIZE <= point.x() < rect.left() and rect.top() <= point.y() <= rect.bottom():
            self.setCursor(Qt.CursorShape.SplitVCursor)
            return
        for index in range(len(self.zones) - 1, -1, -1):
            if self.zone_rect(self.zones[index]).contains(point):
                edges = self.resize_edges_at(point, self.zones[index])
                self.setCursor(self.cursor_for_edges(edges) if edges else Qt.CursorShape.OpenHandCursor)
                return
        self.unsetCursor()

    def mouseReleaseEvent(self, event):
        if event.button() != Qt.MouseButton.LeftButton:
            return
        if self.drawing_start is not None:
            end = self.snap_point(self.percent_point(event.position()))
            x, y = min(self.drawing_start.x(), end.x()), min(self.drawing_start.y(), end.y())
            width, height = abs(end.x() - self.drawing_start.x()), abs(end.y() - self.drawing_start.y())
            if width >= 2 and height >= 2:
                self.zones.append({"x": round(x), "y": round(y), "width": round(width), "height": round(height)})
                self.selected = len(self.zones) - 1
                self.selectionChanged.emit(self.selected)
                self.changed.emit()
            self.drawing_start = self.drawing_current = None
        if self.drag_start is not None:
            self.drag_start = self.drag_zone = None
            self.interaction = None
            self.resize_edges = set()
            self.changed.emit()
        self.update()


class Editor(QMainWindow):
    def __init__(self):
        super().__init__()
        self.layouts = read_layouts()
        self.current = 0
        self.setWindowTitle("KZones Layout Editor")
        self.resize(1050, 690)
        self.build_ui()
        self.load_layout()

    def build_ui(self):
        root = QWidget()
        self.setCentralWidget(root)
        layout = QVBoxLayout(root)
        header = QHBoxLayout()
        header.addWidget(QLabel("Layout:"))
        self.layout_picker = QComboBox()
        self.layout_picker.currentIndexChanged.connect(self.change_layout)
        header.addWidget(self.layout_picker, 1)
        for title, callback in [("New", self.add_layout), ("Duplicate", self.duplicate_layout), ("Remove", self.remove_layout)]:
            button = QPushButton(title)
            button.clicked.connect(callback)
            header.addWidget(button)
        layout.addLayout(header)

        split = QSplitter()
        self.canvas = LayoutCanvas()
        self.canvas.changed.connect(self.canvas_changed)
        self.canvas.selectionChanged.connect(self.zone_selected)
        self.canvas.dividerRequested.connect(self.add_divider)
        split.addWidget(self.canvas)
        controls = QWidget()
        controls.setMinimumWidth(290)
        right = QVBoxLayout(controls)
        form = QFormLayout()
        self.name = QLineEdit()
        self.name.editingFinished.connect(self.update_layout_info)
        self.padding = QSpinBox(); self.padding.setRange(0, 100); self.padding.setSuffix(" px")
        self.padding.valueChanged.connect(self.update_layout_info)
        self.floating = QCheckBox("Floating layout (free positioning)")
        self.floating.setToolTip("Off: zones snap to the grid and to nearby zone edges. On: zones can be placed freely.")
        self.floating.toggled.connect(self.update_floating)
        form.addRow("Name:", self.name)
        form.addRow("Padding:", self.padding)
        form.addRow("Mode:", self.floating)
        right.addLayout(form)
        right.addWidget(QLabel("Zones (draw in the preview to add one):"))
        self.zone_list = QListWidget()
        self.zone_list.currentRowChanged.connect(self.list_selected)
        right.addWidget(self.zone_list, 1)
        buttons = QHBoxLayout()
        for title, callback in [("Split left/right", lambda: self.split_zone("vertical")), ("Split top/bottom", lambda: self.split_zone("horizontal"))]:
            button = QPushButton(title); button.clicked.connect(callback); buttons.addWidget(button)
        right.addLayout(buttons)
        remove_zone = QPushButton("Remove selected zone")
        remove_zone.clicked.connect(self.remove_zone)
        right.addWidget(remove_zone)
        instructions = QLabel("Drag a zone to move it; drag its handles to resize. Click the top/left ruler to add a divider.")
        instructions.setWordWrap(True)
        right.addWidget(instructions, 0)
        split.addWidget(controls)
        split.setStretchFactor(0, 3)
        layout.addWidget(split, 1)
        footer = QHBoxLayout()
        footer.addWidget(QLabel("Save applies the layout immediately to KWin."))
        footer.addStretch(1)
        save = QPushButton("Save and apply")
        save.clicked.connect(self.save)
        footer.addWidget(save)
        layout.addLayout(footer)
        delete = QAction(self)
        delete.setShortcut("Delete")
        delete.triggered.connect(self.remove_zone)
        self.addAction(delete)

    def current_layout(self):
        return self.layouts[self.current]

    def refresh_picker(self):
        self.layout_picker.blockSignals(True)
        self.layout_picker.clear()
        self.layout_picker.addItems([item.get("name", "Unnamed layout") for item in self.layouts])
        self.layout_picker.setCurrentIndex(self.current)
        self.layout_picker.blockSignals(False)

    def load_layout(self):
        self.current = max(0, min(self.current, len(self.layouts) - 1))
        selected = self.canvas.selected
        item = self.current_layout()
        item.setdefault("name", "Untitled layout")
        item.setdefault("padding", 0)
        item.setdefault("zones", [])
        item.setdefault("floating", False)
        self.refresh_picker()
        self.name.setText(item["name"])
        self.padding.blockSignals(True); self.padding.setValue(item["padding"]); self.padding.blockSignals(False)
        self.floating.blockSignals(True); self.floating.setChecked(item["floating"]); self.floating.blockSignals(False)
        self.canvas.set_floating(item["floating"])
        self.canvas.set_zones(item["zones"])
        self.refresh_zones(selected)

    def refresh_zones(self, selected=-1):
        self.zone_list.blockSignals(True)
        self.zone_list.clear()
        for index, zone in enumerate(self.current_layout()["zones"]):
            self.zone_list.addItem(f"{index + 1}: x {zone['x']}, y {zone['y']}, {zone['width']} x {zone['height']}")
        self.zone_list.setCurrentRow(selected)
        self.zone_list.blockSignals(False)

    def change_layout(self, index):
        if index >= 0:
            self.update_layout_info()
            self.current = index
            self.load_layout()

    def update_layout_info(self):
        if not self.layouts:
            return
        item = self.current_layout()
        item["name"] = self.name.text().strip() or "Untitled layout"
        item["padding"] = self.padding.value()
        self.refresh_picker()

    def update_floating(self, floating):
        item = self.current_layout()
        item["floating"] = floating
        self.canvas.set_floating(floating)

    def canvas_changed(self):
        self.refresh_zones(self.canvas.selected)

    def zone_selected(self, index):
        self.refresh_zones(index)

    def list_selected(self, index):
        if index != self.canvas.selected:
            self.canvas.selected = index
            self.canvas.update()

    def add_layout(self):
        self.update_layout_info()
        self.layouts.append({
            "name": f"Layout {len(self.layouts) + 1}",
            "padding": 0,
            "floating": False,
            "zones": [{"x": 0, "y": 0, "width": 100, "height": 100}],
        })
        self.current = len(self.layouts) - 1
        self.load_layout()

    def duplicate_layout(self):
        self.update_layout_info()
        clone = json.loads(json.dumps(self.current_layout()))
        clone["name"] = f"{clone['name']} copy"
        self.layouts.append(clone)
        self.current = len(self.layouts) - 1
        self.load_layout()

    def remove_layout(self):
        if len(self.layouts) == 1:
            QMessageBox.warning(self, "Cannot remove layout", "At least one layout is required.")
            return
        del self.layouts[self.current]
        self.current = min(self.current, len(self.layouts) - 1)
        self.load_layout()

    def remove_zone(self):
        index = self.canvas.selected
        zones = self.current_layout()["zones"]
        if 0 <= index < len(zones):
            del zones[index]
            self.canvas.selected = -1
            self.canvas.update()
            self.refresh_zones()

    def split_zone(self, direction):
        index = self.canvas.selected
        zones = self.current_layout()["zones"]
        if not 0 <= index < len(zones):
            QMessageBox.information(self, "Select a zone", "Select a zone in the preview first.")
            return
        zone = zones[index]
        if direction == "vertical":
            first = dict(zone); second = dict(zone)
            first["width"] = zone["width"] // 2
            second["x"] = zone["x"] + first["width"]
            second["width"] = zone["width"] - first["width"]
        else:
            first = dict(zone); second = dict(zone)
            first["height"] = zone["height"] // 2
            second["y"] = zone["y"] + first["height"]
            second["height"] = zone["height"] - first["height"]
        if not first["width"] or not first["height"] or not second["width"] or not second["height"]:
            QMessageBox.warning(self, "Zone too small", "This zone cannot be split further.")
            return
        zones[index:index + 1] = [first, second]
        self.canvas.set_zones(zones)
        self.canvas.selected = index
        self.canvas.update()
        self.refresh_zones(index)

    def add_divider(self, direction, position):
        """Split every zone crossed by a clicked top or left ruler position."""
        zones = self.current_layout()["zones"]
        axis = "x" if direction == "vertical" else "y"
        size = "width" if direction == "vertical" else "height"
        new_zones = []
        split_count = 0
        for zone in zones:
            start = zone[axis]
            end = start + zone[size]
            if start + LayoutCanvas.MIN_ZONE_SIZE <= position <= end - LayoutCanvas.MIN_ZONE_SIZE:
                first = dict(zone)
                second = dict(zone)
                first[size] = position - start
                second[axis] = position
                second[size] = end - position
                new_zones.extend((first, second))
                split_count += 1
            else:
                new_zones.append(zone)
        if not split_count:
            QMessageBox.information(self, "No zone crossed", "Click inside an existing zone, away from its edge, to create a divider.")
            return
        zones[:] = new_zones
        self.canvas.set_zones(zones)
        self.refresh_zones()

    def save(self):
        self.update_layout_info()
        if any(not layout["zones"] for layout in self.layouts):
            QMessageBox.warning(self, "Empty layout", "Every layout must contain at least one zone.")
            return
        payload = json.dumps(self.layouts, separators=(",", ":"))
        result = subprocess.run(
            ["kwriteconfig6", "--file", "kwinrc", "--group", "Script-kzones", "--key", "layoutsJson", payload],
            text=True, capture_output=True, check=False,
        )
        if result.returncode:
            QMessageBox.critical(self, "Save failed", result.stderr or "kwriteconfig6 failed")
            return
        subprocess.run(["qdbus6", "org.kde.KWin", "/KWin", "org.kde.KWin.reconfigure"], check=False)
        QMessageBox.information(self, "KZones", "Saved and applied to KWin.")


if __name__ == "__main__":
    app = QApplication(sys.argv)
    window = Editor()
    window.show()
    sys.exit(app.exec())
