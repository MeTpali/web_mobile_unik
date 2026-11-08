"""Рендер собственных SVG в PNG 86×86 через системные librsvg и cairo."""
from ctypes import CDLL, POINTER, c_char_p, c_int, c_void_p
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
rsvg = CDLL('librsvg-2.so.2')
cairo = CDLL('libcairo.so.2')
gobject = CDLL('libgobject-2.0.so.0')
rsvg.rsvg_handle_new_from_file.argtypes = [c_char_p, POINTER(c_void_p)]
rsvg.rsvg_handle_new_from_file.restype = c_void_p
rsvg.rsvg_handle_render_cairo.argtypes = [c_void_p, c_void_p]
rsvg.rsvg_handle_render_cairo.restype = c_int
cairo.cairo_image_surface_create.argtypes = [c_int, c_int, c_int]
cairo.cairo_image_surface_create.restype = c_void_p
cairo.cairo_create.argtypes = [c_void_p]
cairo.cairo_create.restype = c_void_p
cairo.cairo_surface_write_to_png.argtypes = [c_void_p, c_char_p]
cairo.cairo_surface_write_to_png.restype = c_int
cairo.cairo_destroy.argtypes = [c_void_p]
cairo.cairo_surface_destroy.argtypes = [c_void_p]
gobject.g_object_unref.argtypes = [c_void_p]

for number in (2, 3):
    source = ROOT / f'tools/icons/tasks-lab{number}.svg'
    destination = ROOT / f'lab{number}/client/icons/86x86/ru.kirik.taskslab{number}.png'
    icon = rsvg.rsvg_handle_new_from_file(str(source).encode(), None)
    if not icon:
        raise RuntimeError(f'Не удалось прочитать {source}')
    surface = cairo.cairo_image_surface_create(0, 86, 86)
    context = cairo.cairo_create(surface)
    try:
        if not rsvg.rsvg_handle_render_cairo(icon, context):
            raise RuntimeError(f'Не удалось отрисовать {source}')
        if cairo.cairo_surface_write_to_png(surface, str(destination).encode()):
            raise RuntimeError(f'Не удалось записать {destination}')
    finally:
        cairo.cairo_destroy(context)
        cairo.cairo_surface_destroy(surface)
        gobject.g_object_unref(icon)
    print(destination)
