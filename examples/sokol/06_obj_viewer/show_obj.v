/**********************************************************************
*
* .obj viewer
*
* Copyright (c) 2021 Dario Deledda. All rights reserved.
* Use of this source code is governed by an MIT license
* that can be found in the LICENSE file.
*
* Example .obj model of V from SurmanPP
*
* HOW TO COMPILE SHADERS:
* - download the sokol shader convertor tool from https://github.com/floooh/sokol-tools-bin/archive/pre-feb2021-api-changes.tar.gz
* ( also look at https://github.com/floooh/sokol-tools/blob/master/docs/sokol-shdc.md )
* - compile the .glsl shader with:
* linux  :  sokol-shdc --input gouraud.glsl --output gouraud.h --slang glsl330
* windows:  sokol-shdc.exe --input gouraud.glsl --output gouraud.h --slang glsl330
*
* --slang parameter can be:
* - glsl330: desktop GL
* - glsl100: GLES2 / WebGL
* - glsl300es: GLES3 / WebGL2
* - hlsl4: D3D11
* - hlsl5: D3D11
* - metal_macos: Metal on macOS
* - metal_ios: Metal on iOS device
* - metal_sim: Metal on iOS simulator
* - wgpu: WebGPU
*
* you can have multiple platforms at the same time passing parameters like this: --slang glsl330:hlsl5:metal_macos
* for further infos have a look at the sokol shader tool docs.
*
* ALTERNATIVE .OBJ MODELS:
* you can load alternative models putting them in the "assets/model" folder with or without their .mtl file.
* use the program help for further instructions.
*
* TODO:
* - frame counter
**********************************************************************/
import gg
import gg.m4
import gx
import math
import sokol.sapp
import sokol.gfx
import sokol.sgl
import time

import os
import obj

// GLSL Include and functions

#flag -I @VROOT/.
#include "gouraud.h" #Please use sokol-shdc to generate the necessary rt_glsl.h file from rt_glsl.glsl (see the instructions at the top of this file)
//fn C.gouraud_shader_desc(gfx.Backend) &C.sg_shader_desc
fn C.gouraud_shader_desc() &C.sg_shader_desc

const (
	win_width  = 600
	win_height = 600
	bg_color   = gx.white
)

struct App {
mut:
	gg          &gg.Context
	texture     C.sg_image
	init_flag   bool
	frame_count int

	mouse_x     int = -1
	mouse_y     int = -1
	scroll_y    int      //mouse wheel value

	// time
	ticks       i64
	
	// model
	obj_part    &obj.ObjPart
	n_vertex    u32
	
	// init parameters
	file_name   string
	single_material_flag bool
}

/******************************************************************************
* Draw functions
******************************************************************************/
[inline] 
fn vec4(x f32, y f32, z f32, w f32) m4.Vec4 {
	return m4.Vec4{e:[x, y, z, w]!}
}

fn calc_matrices(w f32, h f32, rx f32, ry f32, in_scale f32, pos m4.Vec4) obj.Mats {
	proj := m4.perspective(60, w/h, 0.01, 100.0)  // set far plane to 100 fro the zoom function
	view := m4.look_at(vec4(f32(0.0) ,0 , 6, 0), vec4(f32(0), 0, 0, 0), vec4(f32(0), 1, 0, 0))
	view_proj := view * proj

	rxm := m4.rotate(m4.rad(rx), vec4(f32(1), 0, 0, 0))
	rym := m4.rotate(m4.rad(ry), vec4(f32(0), 1, 0, 0))
	
	model_pos := m4.unit_m4().translate(pos)

	model_m :=  (rym * rxm) * model_pos
	scale_m := m4.scale(vec4(in_scale, in_scale, in_scale, 1))

	mv := scale_m * model_m        // model view
	nm := mv.inverse().transpose() // normal matrix
	mvp :=  mv * view_proj         // model view projection
	
	return obj.Mats{mv:mv, mvp:mvp, nm:nm}
}

fn draw_model(app App, model_pos m4.Vec4) u32 {
	if app.init_flag == false {
		return 0
	}

	ws := gg.window_size_real_pixels()
	dw := ws.width/2
	dh := ws.height/2

	mut scale := f32(1)
	if app.obj_part.radius > 1 {
		scale = 1/(app.obj_part.radius) 
	} else {
		scale = app.obj_part.radius
	}
	scale *= 3
	
	// *** vertex shader uniforms ***
	rot := [f32(app.mouse_y), f32(app.mouse_x)]
	mut zoom_scale := scale + f32(app.scroll_y) / (app.obj_part.radius*4)
	mats := calc_matrices(dw, dh, rot[0], rot[1] , zoom_scale, model_pos)
	
	mut tmp_vs_param := obj.Tmp_vs_param{
		mv:  mats.mv,
		mvp: mats.mvp,
		nm:  mats.nm
	}
	
	// *** fragment shader uniforms ***
	time_ticks := f32(time.ticks() - app.ticks) / 1000
	radius_light  := f32(app.obj_part.radius)
	x_light       := f32(math.cos(time_ticks) * radius_light)
	z_light       := f32(math.sin(time_ticks) * radius_light)

	mut tmp_fs_params := obj.Tmp_fs_param{}
	tmp_fs_params.ligth = m4.vec3(x_light, radius_light, z_light)
	
	sd := obj.Shader_data{
		vs_data: &tmp_vs_param
		vs_len:  int(sizeof(tmp_vs_param))
		fs_data: &tmp_fs_params
		fs_len:  int(sizeof(tmp_fs_params))
	}

	return app.obj_part.bind_and_draw_all(sd)	
}

fn frame(mut app App) {
	ws := gg.window_size_real_pixels()

	// clear
	mut color_action := C.sg_color_attachment_action{
		action: gfx.Action(C.SG_ACTION_CLEAR)
	}
	color_action.val[0] = 0
	color_action.val[1] = 0
	color_action.val[2] = 0
	color_action.val[3] = 1.0
	mut pass_action := C.sg_pass_action{}
	pass_action.colors[0] = color_action
	gfx.begin_default_pass(&pass_action, ws.width, ws.height)

	// render the data
	draw_start_glsl(app)
	draw_model(app, m4.Vec4{})
// uncoment if you want a raw benchmark mode
/*	
	mut n_vertex_drawn := u32(0)
	n_x_obj := 20

	for x in 0..n_x_obj {
		for z in 0..30 {
			for y in 0..4 {
				n_vertex_drawn += draw_model(app, m4.Vec4{e:[f32((x-(n_x_obj>>1))*3),-3 + y*3,f32(-6*z),1]!})
			}
		}
	}
*/	
	draw_end_glsl(app)
		
	//println("v:$n_vertex_drawn")
	app.frame_count++
}

fn draw_start_glsl(app App){
	if app.init_flag == false {
		return
	}
	ws := gg.window_size_real_pixels()
	gfx.apply_viewport(0, 0, ws.width, ws.height, true)
}

fn draw_end_glsl(app App){
	gfx.end_pass()
	gfx.commit()
}

/******************************************************************************
* Init / Cleanup
******************************************************************************/
fn my_init(mut app App) {
	mut object := &obj.ObjPart{}
	obj_file_lines := obj.read_lines_from_file(app.file_name)
	object.parse_obj_buffer(obj_file_lines, app.single_material_flag)
	object.summary()
	app.obj_part = object

	// set max vertices,
	// for a large number of the same type of object it is better use the instances!!
	desc := sapp.create_desc()
	gfx.setup(&desc)
	sgl_desc := C.sgl_desc_t{
		max_vertices: 128 * 65536
	}
	sgl.setup(&sgl_desc)
	
	// 1x1 pixel white, default texture
	unsafe {
		tmp_txt := malloc(4)
		tmp_txt[0] = byte(0xFF)
		tmp_txt[1] = byte(0xFF)
		tmp_txt[2] = byte(0xFF)
		tmp_txt[3] = byte(0xFF)
		app.texture = obj.create_texture(1, 1, tmp_txt)
		free(tmp_txt)
	}
	
	// glsl
	app.obj_part.init_render_data(app.texture)
	app.init_flag = true
}

fn cleanup(mut app App) {
	gfx.shutdown()
/*
	for _, mat in app.obj_part.texture {
		obj.destroy_texture(mat)
	}
*/	
}

/******************************************************************************
* events handling
******************************************************************************/
fn my_event_manager(mut ev gg.Event, mut app App) {
	if ev.typ == .mouse_move {
		app.mouse_x = int(ev.mouse_x)
		app.mouse_y = int(ev.mouse_y)
	}
	
	if ev.scroll_y != 0 {
		app.scroll_y += int(ev.scroll_y)
	}
	
	if ev.typ == .touches_began || ev.typ == .touches_moved {
		if ev.num_touches > 0 {
			touch_point := ev.touches[0]
			app.mouse_x = int(touch_point.pos_x)
			app.mouse_y = int(touch_point.pos_y)
		}
	}
}

/******************************************************************************
* Main
******************************************************************************/
[console] // is needed for easier diagnostics on windows
fn main() {
/*
	obj.tst()
	exit(0)
*/

	// App init
	mut app := &App{
		gg:       0
		obj_part: 0
	}
	
	app.file_name            = "v.obj" // default object is the v logo
	app.single_material_flag = false
	$if !android {
		if os.args.len > 3 || (os.args.len >= 2 && os.args[1] in ['-h', '--help', '\\?', '-?']) {
			eprintln('Usage:\nshow_obj [file_name:string] [single_material_flag:(true|false)]\n')
			eprintln('file_name           : name of the .obj file, it must be in the folder "assets/models"')
			eprintln('                      if no file name is passed the default V logo will be showed.')
			eprintln('                      if you want custom models you can put them in the folder "assets/models".')
			eprintln('single_material_flag: if true the viewer use for all the model\'s parts the default material\n')
			exit(0)
		}
		
		if os.args.len >= 2 { 
			app.file_name = os.args[1]
		}
		if os.args.len >= 3 {
			app.single_material_flag = os.args[2].bool()
		}
		println("Loading model: $app.file_name")
		println("Using single material: $app.single_material_flag")
	}
	
	app.gg = gg.new_context(
		width: win_width
		height: win_height
		use_ortho: true // This is needed for 2D drawing
		create_window: true
		window_title: 'V Wavefront OBJ viewer - Use the mouse wheel to zoom'
		user_data: app
		bg_color: bg_color
		frame_fn: frame
		init_fn: my_init
		cleanup_fn: cleanup
		event_fn: my_event_manager
	)

	app.ticks = time.ticks()
	app.gg.run()
}
