/*
 * Copyright (c) 2015, Nicolas Cannasse
 *
 * Permission to use, copy, modify, and/or distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
 * SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR
 * IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 */
package lvl;
import haxe.Timer;
import cdb.Data;
import js.jquery.Helper.*;
import js.jquery.JQuery;

class Palette {

	static var colorPalette = [
		0xFF0000, 0x00FF00,
		0xFF00FF, 0x00FFFF, 0xFFFF00,
		0xFFFFFF,
		0x0080FF, 0x00FF80, 0x8000FF, 0x80FF00, 0xFF0080, 0xFF8000,
	];

	var p : JQuery;
	var level : Level;
	var perTileProps : Array<Column>;
	var perTileGfx : Map<String, lvl.LayerGfx>;
	var currentLayer : LayerData;
	public var scale : Float;
	public var select : lvl.Image;
	public var small : Bool = false;
	public var paintMode : Bool = false;
	public var randomMode : Bool = false;
	public var mode  : Null<String> = null;
	public var modeCursor : Int = 0;
	public var gridFill: Bool = false;

	public function new(level) {
		this.level = level;
	}

	public function init() {

		perTileProps = [];
		for( c in level.sheet.columns )
			if( c.name == "tileProps" && (c.type == TList || c.type == TProperties) )
				perTileProps = level.sheet.getSub(c).columns;

		perTileGfx = new Map();
		for( c in perTileProps )
			switch( c.type ) {
			case TRef(s):
				var g = new lvl.LayerGfx(level);
				g.fromSheet(level.model.getSheet(s), 0xFF0000);
				perTileGfx.set(c.name, g);
			default:
			}
	}

	function getDefault( c : Column ) : Dynamic {
		return level.model.base.getDefault(c);
	}

	function getTileProp(x, y,create=true) {
		var l = currentLayer;
		var a = x + y * l.stride;
		var p = currentLayer.tileProps.props[a];
		if( p == null ) {
			if( !create ) return null;
			p = { };
			for( c in perTileProps ) {
				var v = getDefault(c);
				if( v != null ) Reflect.setField(p, c.name, v);
			}
			currentLayer.tileProps.props[a] = p;
		}
		return p;
	}

	public function getTileProps(file,stride,max) {
		var p : TilesetProps = Reflect.field(level.sheet.props.level.tileSets,file);
		if( p == null ) {
			p = {
				stride : stride,
				sets : [],
				props : [],
			};
			Reflect.setField(level.sheet.props.level.tileSets, file, p);
		} else {
			if( p.sets == null ) p.sets = [];
			if( p.props == null ) p.props = [];
			Reflect.deleteField(p, "tags");
			if( p.stride == null ) p.stride = stride else if( p.stride != stride ) {
				var out = [];
				for( y in 0...Math.ceil(p.props.length / p.stride) )
					for( x in 0...p.stride )
						out[x + y * stride] = p.props[x + y * p.stride];
				while( out.length > 0 && (out[out.length - 1] == null || out.length > max) )
					out.pop();
				p.props = out;
				p.stride = stride;
			}
			if( p.props.length > max ) p.props.splice(max, p.props.length - max);
			for( s in p.sets.copy() )
				if( s.x + s.w > stride || (s.y+s.h)*stride > max )
					p.sets.remove(s);
		}
		return p;
	}

	function saveTileProps() {
		var pr = currentLayer.tileProps.props;
		for( i in 0...pr.length ) {
			var p = pr[i];
			if( p == null ) continue;
			var def = true;
			for( c in perTileProps ) {
				var v = Reflect.field(p, c.name);
				if( v != null && v != getDefault(c) ) {
					def = false;
					break;
				}
			}
			if( def )
				pr[i] = null;
		}
		while( pr.length > 0 && pr[pr.length - 1] == null )
			pr.pop();
		level.save();
		level.setCursor();
	}

	public function reset() {
		if( p != null ) {
			p.remove();
			select = null;
		}
	}

	public function ensureBarIsOnScreen() {
		Timer.delay(() -> {
			var paletteJ = J(".level .palette");
			var bar = paletteJ.find(".bar");
			var ww = js.node.webkit.Window.get().width;
			var wh = js.node.webkit.Window.get().height;
			var bOff = bar.offset();
			if( bOff.left < 0 ) {
				paletteJ.css("left", 0);
			}
			if( bOff.top < 0 ) {
				paletteJ.css("top", 0);
			}
			if( bOff.left > ww - bar.outerWidth() ) {
				paletteJ.css("left", ww - (paletteJ.width() + 200));
			}
			if( bOff.top > wh - bar.outerHeight() ) {
				paletteJ.css("top", wh - (paletteJ.height() + 200));
			}
		}, 0);
	}

	public function realignPaletteObject() {

	}

	public function layerChanged( l : LayerData, ?resetScale: Bool = true ) {

		trace("layerChanged");
		// Assign the current layer

		if(resetScale){
			scale = 1;
		}

		currentLayer = l;
	
		// Find and append the palette content to the level content
		p = J(J("#paletteContent").html()).appendTo(@:privateAccess level.content);

	
		
		
		// Toggle the 'small' class based on the 'small' variable
		p.toggleClass("small", small);
	
		// Create an image from the canvas element
		var i = lvl.Image.fromCanvas(cast p.find("canvas.view")[0]);
		
		// Determine max width and calculate palette width
		var maxWidth = js.node.webkit.Window.get().width / 2;


		var paletteJ = J(".level .palette");
		var bar = p.find(".bar");

		//paletteJ.offset({left: 300, top: 300});

		// Make bar draggable
		var dragging = false;
		var startDragX = 0;
		var startDragY = 0;
		var lastDragX = 0;
		var lastDragY = 0;

		var drag = (e: Dynamic) -> {
			if(dragging){
				var pOff = paletteJ.offset();
				var deltaX = e.pageX - lastDragX;
				var deltaY = e.pageY - lastDragY;
				//trace("e.pageX" + e.pageX + "e.pageY: " + e.pageY + " bOff.top: " + bOff.top + " pOff.top: " + pOff.top, "bOff.left: " + bOff.left + " pOff.left: " + pOff.left);
				paletteJ.offset({top: pOff.top + deltaY, left: pOff.left + deltaX});
				lastDragX = e.pageX;
				lastDragY = e.pageY;
			}
		};

		bar.mousedown((e: Dynamic) -> {
			trace("bar.mousedown");
			dragging = true;
			startDragX = e.pageX;
			startDragY = e.pageY;
			lastDragX = e.pageX;
			lastDragY = e.pageY;

			J(".level").on("mousemove.palette", drag);
		});

		bar.mouseup(function(e) {
			dragging = false;
			J(".level").off("mousemove.palette");
			ensureBarIsOnScreen();
		});

		var palWidth = l.stride * level.tileSize * scale;
	
		// Adjust zoom until the palette width fits within the max width
	//	while(palWidth > maxWidth){
			//scale = scale - 0.1;
	//		palWidth = l.stride * level.tileSize * scale;
		//}

		var smallFactor = small ? 0 : 1;
		paletteJ.css({
			//"width": "300px",
			//"height": bar.height() + (smallFactor * l.height * level.tileSize * scale) + "px"
		});

		ensureBarIsOnScreen();
		
		if(small){
			J(".level .palette").offset(J(".level .bar").offset());
			J(".level .palette").css({
				"height": J(".level .bar").height() + "px"
			});
		}
	
		// Calculate the tile size based on the zoom level
		var tsize = Std.int(level.tileSize * scale);
		var scaleUp = 0, scaleDown = 0;
	
		// Set the size of the image canvas based on stride and height
		i.setSize(l.stride * (tsize + 1), l.height * (tsize + 1));
	
		// Loop through each tile image in the layer
		for( n in 0...l.images.length ) {
			var x = (n % l.stride) * (tsize + 1);
			var y = Std.int(n / l.stride) * (tsize + 1);
			var li = l.images[n];
	
			// Draw the image directly if it matches the tile size
			if( li.width == tsize && li.height == tsize ) {
				i.draw(li, x, y);
			} else {
				// Calculate scale width and height
				var sw = tsize / li.width;
				var sh = tsize / li.height;
				if( sw > 1 ) scaleUp++ else if( sw < 1 ) scaleDown++;
				if( sh > 1 ) scaleUp++ else if( sh < 1 ) scaleDown++;
				i.drawScaled(li, x, y, tsize, tsize);
			}
		}
	
		// Adjust image rendering mode if required
		if( scaleUp > scaleDown && scaleUp != 0 ) {
			J(i.getCanvas()).css("image-rendering", "pixelated");
		}
	
		// Select elements for interaction
		var jsel = J(".level .palette .content .select");
		var jpreview = p.find(".preview").hide();
		var ipreview = lvl.Image.fromCanvas(cast jpreview.find("canvas")[0]);
		select = lvl.Image.fromCanvas(cast jsel[0]);
		select.setSize(i.width, i.height);
	
		// Toggle active states of different icons
		p.find(".icon.random").toggleClass("active", randomMode);
		p.find(".icon.paint").toggleClass("active", paintMode);
		p.find(".icon.small").toggleClass("active", small);
		p.find(".icon.gridFill").toggleClass("active", gridFill);
	
		// Prevent event propagation for mouse down and up on the palette
		p.mousedown(function(e) e.stopPropagation());
		p.mouseup(function(e) e.stopPropagation());
	
		var curPreview = -1;
		var start = { x : l.currentSelection % l.stride, y : Std.int(l.currentSelection / l.stride), down : false };
	
		// Event handler for mouse down on the selection canvas
		jsel.mousedown(function(e) {
			trace("jsel.mousedown");
			p.find("input[type=text]:focus").blur();
			
			@:privateAccess var scrollX = level.content.find(".content").scrollLeft();
			@:privateAccess var scrollY = level.content.find(".content").scrollTop();
			var o = jsel.offset();
		//	o.left -= scrollX;
		//	o.top -= scrollY;

			var x = Std.int((e.pageX - o.left) / (level.tileSize * scale + 1));
			var y = Std.int((e.pageY - o.top) / (level.tileSize * scale + 1));
			//var xScollDisplaced = Std.int((e.pageX - (o.left - scrollX)) / (level.tileSize * scale + 1));
			//var yScrollDisplaced = Std.int((e.pageY - (o.top - scrollY)) / (level.tileSize * scale + 1));

			trace("scrollX: " + scrollX + " scrollY: " + scrollY + " o.left: " + o.left + " o.top: " + o.top + " x: " + x + " y: " + y);
			if( x + y * l.stride >= l.images.length ) return;
	
			if( e.shiftKey ) {
				var x0 = x < start.x ? x : start.x;
				var y0 = y < start.y ? y : start.y;
				var x1 = x < start.x ? start.x : x;
				var y1 = y < start.y ? start.y : y;
				l.currentSelection = x0 + y0 * l.stride;
				l.currentSelectionWidth = x1 - x0 + 1;
				l.currentSelectionHeight = y1 - y0 + 1;
				l.saveState();
				level.setCursor();
			} else {
				start.x = x;
				start.y = y;
				if( l.tileProps != null && (mode == null || mode == "t_objects") )
					for( p in l.tileProps.sets )
						if( x >= p.x && y >= p.y && x < p.x + p.w && y < p.y + p.h && p.t == Object ) {
							l.currentSelection = p.x + p.y * l.stride;
							l.currentSelectionWidth = p.w;
							l.currentSelectionHeight = p.h;
							l.saveState();
							level.setCursor();
							return;
						}
				start.down = true;
				@:privateAccess level.mouseCapture = jsel;
				l.currentSelection = x + y * l.stride;
				level.setCursor();
			}
	
			var prop = getProp();
			if( prop != null ) {
	
				var pick = e.which == 3;
	
				switch( prop.type ) {
					case TBool: {
						if( !pick ) {
							var v = getTileProp(x, y);
							Reflect.setField(v, prop.name, !Reflect.field(v, prop.name));
							saveTileProps();
						}
					}
					case TRef(_): {
						var c = perTileGfx.get(prop.name);
						if( pick ) {
							var idx = c.idToIndex.get(Reflect.field(getTileProp(x, y), prop.name));
							modeCursor = idx == null ? -1 : idx;
							level.setCursor();
							return;
						}
						var v;
						if( modeCursor < 0 )
							v = getDefault(prop);
						else
							v = c.indexToId[modeCursor];
						if( v == null )
							Reflect.deleteField(getTileProp(x, y), prop.name);
						else
							Reflect.setField(getTileProp(x, y), prop.name, v);
						saveTileProps();
					}
					case TEnum(_): {
						if( pick ) {
							var idx : Null<Int> = Reflect.field(getTileProp(x, y), prop.name);
							modeCursor = idx == null ? -1 : idx;
							level.setCursor();
							return;
						}
						var v;
						if( modeCursor < 0 )
							v = getDefault(prop);
						else
							v = modeCursor;
						if( v == null )
							Reflect.deleteField(getTileProp(x, y), prop.name);
						else
							Reflect.setField(getTileProp(x, y), prop.name, v);
						saveTileProps();
					}
					default: {}
				}
			}
		});
	
		// Event handler for mouse movement on the selection canvas
		jsel.mousemove(function(e) {
	
			@:privateAccess var scrollX = level.content.find(".content").scrollLeft();
			@:privateAccess var scrollY = level.content.find(".content").scrollTop();
			var o = jsel.offset();
			//o.left -= scrollX;
			//o.top -= scrollY;
			
			var x = Std.int((e.pageX - o.left) / (level.tileSize * scale + 1));
			var y = Std.int((e.pageY - o.top) / (level.tileSize * scale + 1));
			var infos = x + "," + y;

	
			var id = x + y * l.stride;
			if( id >= l.images.length || l.blanks[id] ) {
				curPreview = -1;
				jpreview.hide();
			} else {
				if( curPreview != id ) {
					curPreview = id;
					jpreview.show();
					ipreview.fill(0xFF400040);
					ipreview.copyFrom(l.images[id]);
				}
				if( l.names != null )
					infos += " "+l.names[id];
			}
			if( l.tileProps != null )
				@:privateAccess level.content.find(".cursorPosition").text(infos);
			else
				p.find(".infos").text(infos);
	
			if( !start.down ) return;
			var x0 = x < start.x ? x : start.x;
			var y0 = y < start.y ? y : start.y;
			var x1 = x < start.x ? start.x : x;
			var y1 = y < start.y ? start.y : y;
			l.currentSelection = x0 + y0 * l.stride;
			l.currentSelectionWidth = x1 - x0 + 1;
			l.currentSelectionHeight = y1 - y0 + 1;
			l.saveState();
			level.setCursor();
		});
	
		// Event handler for mouse leaving the selection canvas
		jsel.mouseleave(function(e) {
			if( l.tileProps != null )
				@:privateAccess level.content.find(".cursorPosition").text("");
			else
				p.find(".infos").text("");
			curPreview = -1;
			jpreview.hide();
		});
	
		// Event handler for mouse leaving the palette
		p.mouseleave(function(_) {
			start.down = false;
		});
	
		// Event handler for mouse movement on the palette
		p.mousemove(function(e) {
			@:privateAccess {
				// handle cascading
				level.mousePos.x = Std.int(e.pageX);
				level.mousePos.y = Std.int(e.pageY);
				level.updateCursorPos();
				if( level.selection == null ) level.cursor.hide();
			}
		});
	
		// Event handler for mouse up on the palette
		p.mouseup(function(_) {
			start.down = false;
			@:privateAccess level.content.mouseup();
		});
	}

	public function updateSelect() {
		if( select == null ) return;
		var l = currentLayer;
		select.clear();
		var used = [];
		switch( l.data ) {
		case Tiles(_, data):
			for( k in data ) {
				if( k == 0 ) continue;
				used[k - 1] = true;
			}
		case Layer(data):
			for( k in data )
				used[k] = true;
		case Objects(id, objs):
			for( o in objs ) {
				var id = l.idToIndex.get(Reflect.field(o, id));
				if( id != null ) used[id] = true;
			}
		case TileInstances(_, insts):
			var objs = l.getTileObjects();
			for( i in insts ) {
				var t = objs.get(i.o);
				if( t == null ) {
					used[i.o] = true;
					continue;
				}
				for( dy in 0...t.h )
					for( dx in 0...t.w )
						used[i.o + dx + dy * l.stride] = true;
			}
		}

		var tsize = Std.int(level.tileSize * scale);

		for( i in 0...l.images.length ) {
			if( used[i] ) continue;
			select.fillRect( (i % l.stride) * (tsize + 1), Std.int(i / l.stride) * (tsize + 1), tsize, tsize, 0x30000000);
		}

		var prop = getProp();
		if( prop == null || !prop.type.match(TBool | TRef(_) | TEnum(_)) ) {
			var objs = mode == null ? l.getSelObjects() : [];
			if( objs.length > 1 )
				for( o in objs )
					select.fillRect( o.x * (tsize + 1), o.y * (tsize + 1), (tsize + 1) * o.w - 1, (tsize + 1) * o.h - 1, 0x805BA1FB);
			else
				select.fillRect( (l.currentSelection % l.stride) * (tsize + 1), Std.int(l.currentSelection / l.stride) * (tsize + 1), (tsize + 1) * l.currentSelectionWidth - 1, (tsize + 1) * l.currentSelectionHeight - 1, 0x805BA1FB);
		}
		if( prop != null ) {
			var def : Dynamic = getDefault(prop);
			switch( prop.type ) {
			case TBool:
				var k = 0;
				for( y in 0...l.height )
					for( x in 0...l.stride ) {
						var p = l.tileProps.props[k++];
						if( p == null ) continue;
						var v = Reflect.field(p, prop.name);
						if( v == def ) continue;
						select.fillRect( x * (tsize + 1), y * (tsize + 1), tsize, tsize, v ? 0x80FB5BA1 : 0x805BFBA1);
					}
			case TRef(_):
				var gfx = perTileGfx.get(prop.name);
				var k = 0;
				select.alpha = 0.5;
				for( y in 0...l.height )
					for( x in 0...l.stride ) {
						var p = l.tileProps.props[k++];
						if( p == null ) continue;
						var r = Reflect.field(p, prop.name);
						var v = gfx.idToIndex.get(r);
						if( v == null || r == def ) continue;
						select.drawScaled(gfx.images[v], x * (tsize + 1), y * (tsize + 1), tsize, tsize);
					}
				select.alpha = 1;
			case TEnum(_):
				var k = 0;
				for( y in 0...l.height )
					for( x in 0...l.stride ) {
						var p = l.tileProps.props[k++];
						if( p == null ) continue;
						var v = Reflect.field(p, prop.name);
						if( v == null || v == def ) continue;
						select.fillRect(x * (tsize + 1), y * (tsize + 1), tsize, tsize, colorPalette[v] | 0x80000000);
					}
			case TInt, TFloat, TString, TColor, TFile, TDynamic:
				var k = 0;
				for( y in 0...l.height )
					for( x in 0...l.stride ) {
						var p = l.tileProps.props[k++];
						if( p == null ) continue;
						var v = Reflect.field(p, prop.name);
						if( v == null || v == def ) continue;
						select.fillRect(x * (tsize + 1), y * (tsize + 1), tsize, 1, 0xFFFFFFFF);
						select.fillRect(x * (tsize + 1), y * (tsize + 1), 1, tsize, 0xFFFFFFFF);
						select.fillRect(x * (tsize + 1), (y + 1) * (tsize + 1) - 1, tsize, 1, 0xFFFFFFFF);
						select.fillRect((x + 1) * (tsize + 1) - 1, y * (tsize + 1), 1, tsize, 0xFFFFFFFF);
					}
			default:
				// no per-tile display
			}
		}

		var m = p.find(".mode");
		var sel = p.find(".sel");
		if( l.tileProps == null ) {
			m.hide();
			sel.show();
		} else {
			sel.hide();

			var grounds = [];

			for( s in l.tileProps.sets ) {
				var color;
				switch( s.t ) {
				case Tile:
					continue;
				case Ground:
					if( s.opts.name != null && s.opts.name != "" ) {
						grounds.remove(s.opts.name);
						grounds.push(s.opts.name);
					}
					if( mode != null && mode != "t_ground" ) continue;
					color = mode == null ? 0x00A000 : 0x00FF00;
				case Border:
					if( mode != "t_border" ) continue;
					color = 0x00FFFF;
				case Object:
					if( mode != null && mode != "t_object" ) continue;
					color = mode == null ? 0x800000 : 0xFF0000;
				case Group:
					if( mode != "t_group" ) continue;
					color = 0xFFFFFF;
				}
				color |= 0xFF000000;
				var tsize = Std.int(level.tileSize * scale);
				var px = s.x * (tsize + 1);
				var py = s.y * (tsize + 1);
				var w = s.w * (tsize + 1) - 1;
				var h = s.h * (tsize + 1) - 1;
				select.fillRect(px, py, w, 1, color);
				select.fillRect(px, py + h - 1, w, 1, color);
				select.fillRect(px, py, 1, h, color);
				select.fillRect(px + w - 1, py, 1, h, color);
			}

			var tmode = TileMode.ofString(mode == null ? "" : mode.substr(2));
			var tobj = l.getTileProp(tmode);
			if( tobj == null )
				tobj = { x : 0, y : 0, w : 0, h : 0, t : Tile, opts : { } };

			var baseModes = [for( m in ["tile", "object", "ground", "border", "group"] ) '<option value="t_$m">${m.substr(0,1).toUpperCase()+m.substr(1)}</option>'].join("\n");
			var props = [for( t in perTileProps ) '<option value="${t.name}">${t.name}</option>'].join("\n");
			m.find("[name=mode]").html(baseModes + props).val(mode == null ? "t_tile" : mode);
			m.attr("class", "").addClass("mode");
			if( prop != null ) {
				switch( prop.type ) {
				case TRef(_):
					var gfx = perTileGfx.get(prop.name);
					m.addClass("m_ref");
					var refList = m.find(".opt.refList");
					refList.html("");
					if( prop.opt )
						J("<div>").addClass("icon").addClass("delete").appendTo(refList).toggleClass("active", modeCursor < 0).click(function(_) {
							modeCursor = -1;
							level.setCursor();
						});
					for( i in 0...gfx.images.length ) {
						var d = J("<div>").addClass("icon").css( { background : "url('" + gfx.images[i].getCanvas().toDataURL() + "')" } );
						d.appendTo(refList);
						d.toggleClass("active", modeCursor == i);
						d.attr("title", gfx.names[i]);
						d.click(function(_) {
							modeCursor = i;
							level.setCursor();
						});
					}
				case TEnum(values):
					m.addClass("m_ref");
					var refList = m.find(".opt.refList");
					refList.html("");
					if( prop.opt )
						J("<div>").addClass("icon").addClass("delete").appendTo(refList).toggleClass("active", modeCursor < 0).click(function(_) {
							modeCursor = -1;
							level.setCursor();
						});
					for( i in 0...values.length ) {
						var d = J("<div>").addClass("icon").css( { background : level.toColor(colorPalette[i]), width : "auto" } ).text(values[i]);
						d.appendTo(refList);
						d.toggleClass("active", modeCursor == i);
						d.click(function(_) {
							modeCursor = i;
							level.setCursor();
						});
					}
				case TInt, TFloat, TString, TDynamic:
					m.addClass("m_value");
					var p = getTileProp(l.currentSelection % l.stride, Std.int(l.currentSelection / l.stride),false);
					var v = p == null ? null : Reflect.field(p, prop.name);
					m.find("[name=value]").val(prop.type == TDynamic ? haxe.Json.stringify(v) : v == null ? "" : "" + v);
				default:
				}
			} else if( "t_" + tobj.t != mode ) {
				if( mode == null ) m.addClass("m_tile") else m.addClass("m_create").addClass("c_"+mode.substr(2));
			} else {
				m.addClass("m_"+mode.substr(2)).addClass("m_exists");
				switch( tobj.t ) {
				case Tile, Object:
				case Ground:
					m.find("[name=name]").val(tobj.opts.name == null ? "" : tobj.opts.name);
					m.find("[name=priority]").val("" + (tobj.opts.priority == null ? 0 : tobj.opts.priority));
				case Group:
					m.find("[name=name]").val(tobj.opts.name == null ? "" : tobj.opts.name);
					m.find("[name=value]").val(tobj.opts.value == null ? "" : haxe.Json.stringify(tobj.opts.value)).width(80).width(m.parent().width() - 300);
				case Border:
					var opts = [for( g in grounds ) '<option value="$g">$g</option>'].join("");
					m.find("[name=border_in]").html("<option value='null'>upper</option><option value='lower'>lower</option>" + opts).val(Std.string(tobj.opts.borderIn));
					m.find("[name=border_out]").html("<option value='null'>lower</option><option value='upper'>upper</option>" + opts).val(Std.string(tobj.opts.borderOut));
					m.find("[name=border_mode]").val(Std.string(tobj.opts.borderMode));
				}
			}
			m.show();
		}
	}

	public function getProp() {
		if( mode == null || mode.substr(0, 2) == "t_" || currentLayer.tileProps == null )
			return null;
		for( c in perTileProps )
			if( c.name == mode )
				return c;
		return null;
	}

	var lastHeight: Float = 0;
	
	public function option( name : String, ?val : String ) {
		if( p == null )
			return false;
		var m = TileMode.ofString(mode == null ? "" : mode.substr(2));
		var l = currentLayer;
		if( val != null ) val = StringTools.trim(val);
		switch( name ) {
		case "random":
			randomMode = !randomMode;
			if( l.data.match(TileInstances(_)) ) randomMode = false;
			p.find(".icon.random").toggleClass("active", randomMode);
			level.savePrefs();
			level.setCursor();
			return false;
		case "paint":
			paintMode = !paintMode;
			if( l.data.match(TileInstances(_)) ) paintMode = false;
			level.savePrefs();
			p.find(".icon.paint").toggleClass("active", paintMode);
			return false;
		case "gridFill":
			gridFill = !gridFill;
			level.savePrefs();
			p.find(".icon.gridFill").toggleClass("active", gridFill);
			return false;
		case "zoomIn":
			scale = scale * 2;
			reset();
			trace("scale: " + scale);
			layerChanged(currentLayer, false);
			updateSelect();
			return false;
		case "zoomOut":
			scale = scale / 2;
			reset();
			trace("scale: " + scale);
			layerChanged(currentLayer, false);
			updateSelect();
			return false;
		case "mode":
			mode = val == "t_tile" ? null : val;
			modeCursor = 0;
			level.savePrefs();
			level.setCursor();
		case "toggleMode":
			var s = l.getTileProp(m);
			if( s == null ) {
				s = { x : l.currentSelection % l.stride, y : Std.int(l.currentSelection / l.stride), w : l.currentSelectionWidth, h : l.currentSelectionHeight, t : m, opts : {} };
				l.tileProps.sets.push(s);
			} else
				l.tileProps.sets.remove(s);
			level.setCursor();
		case "name":
			var s = l.getTileProp(m);
			if( s != null )
				s.opts.name = val;
		case "value":
			var p = getProp();
			if( p != null ) {
				var t = getTileProp(l.currentSelection % l.stride, Std.int(l.currentSelection / l.stride));
				var v : Dynamic = switch( p.type ) {
				case TInt: Std.parseInt(val);
				case TFloat: Std.parseFloat(val);
				case TString: val;
				case TDynamic: try level.model.base.parseDynamic(val) catch( e : Dynamic ) null;
				default: throw "assert";
				}
				if( v == null )
					Reflect.deleteField(t, p.name);
				else
					Reflect.setField(t, p.name, v);
				saveTileProps();
				return false;
			}
			var s = l.getTileProp(m);
			if( s != null ) {
				var v = val == null ? s.opts.value : try level.model.base.parseDynamic(val) catch( e : Dynamic ) null;
				if( v == null )
					Reflect.deleteField(s.opts, "value");
				else
					s.opts.value = v;
				this.p.find("[name=value]").val(v == null ? "" : haxe.Json.stringify(v));
			}
		case "priority":
			var s = l.getTileProp(m);
			if( s != null )
				s.opts.priority = Std.parseInt(val);
		case "border_in":
			var s = l.getTileProp(m);
			if( s != null ) {
				if( val == "null" )
					Reflect.deleteField(s.opts,"borderIn");
				else
					s.opts.borderIn = val;
			}
		case "border_out":
			var s = l.getTileProp(m);
			if( s != null ) {
				if( val == "null" )
					Reflect.deleteField(s.opts,"borderOut");
				else
					s.opts.borderOut = val;
			}
		case "border_mode":
			var s = l.getTileProp(m);
			if( s != null ) {
				if( val == "null" )
					Reflect.deleteField(s.opts,"borderMode");
				else
					s.opts.borderMode = val;
			}
		case "small":
			trace("small: " + !small);
			small = !small;
			
			if(small){
				lastHeight = J(".level .palette").height();
				J(".level .palette").offset(J(".level .bar").offset());
				J(".level .palette").css({
					"height": J(".level .bar").height() + "px"
				});
			}
			else {
				J(".level .palette").offset({left: J(".level .palette").offset().left, top: J(".level .palette").offset().top - (lastHeight /*+ J(".level .bar").outerHeight()*/)});
				J(".level .palette").css({
					"height": lastHeight + "px"
				});
			}

			level.savePrefs();
			p.toggleClass("small", small);
			p.find(".icon.small").toggleClass("active", small);
			ensureBarIsOnScreen();
			return false;
		}
		return true;
	}

	

}