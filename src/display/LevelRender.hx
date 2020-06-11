package display;

class LevelRender extends dn.Process {
	static var MAX_FOCUS_PADDING = 200;
	static var _entityRenderCache : Map<Int, h3d.mat.Texture> = new Map();

	public var client(get,never) : Client; inline function get_client() return Client.ME;

	var layerVis : Map<Int,Bool> = new Map();
	var layerWrappers : Map<Int,h2d.Object> = new Map();
	var invalidated = true;

	var bg : h2d.Graphics;
	var grid : h2d.Graphics;

	public var focusLevelX(default,set) : Float = 0.;
	public var focusLevelY(default,set) : Float = 0.;
	public var zoom(default,set) : Float = 3.0;

	public function new() {
		super(client);

		client.ge.listenAll(onGlobalEvent);

		createRootInLayers(client.root, Const.DP_MAIN);

		bg = new h2d.Graphics();
		root.add(bg, Const.DP_BG);
		bg.filter = new h2d.filter.DropShadow(0, 0, 0x0,0.3, 32, true);

		grid = new h2d.Graphics();
		root.add(grid, Const.DP_BG);

		focusLevelX = 0;
		focusLevelY = 0;
	}

	public function setFocus(x,y) {
		focusLevelX = x;
		focusLevelY = y;
	}

	public function fit() {
		focusLevelX = client.curLevel.pxWid*0.5;
		focusLevelY = client.curLevel.pxHei*0.5;
		zoom = 1;
	}

	inline function set_focusLevelX(v) {
		return focusLevelX = client.curLevel==null
			? v
			: M.fclamp( v, -MAX_FOCUS_PADDING/zoom, client.curLevel.pxWid+MAX_FOCUS_PADDING/zoom );
	}

	inline function set_focusLevelY(v) {
		return focusLevelY = client.curLevel==null
			? v
			: M.fclamp( v, -MAX_FOCUS_PADDING/zoom, client.curLevel.pxHei+MAX_FOCUS_PADDING/zoom );
	}

	function set_zoom(v) {
		return zoom = M.fclamp(v, 0.2, 16);
	}

	override function onDispose() {
		super.onDispose();
		client.ge.stopListening(onGlobalEvent);
	}

	function onGlobalEvent(e:GlobalEvent) {
		invalidate();
	}

	public inline function isLayerVisible(l:LayerInstance) {
		return l!=null && ( !layerVis.exists(l.layerDefId) || layerVis.get(l.layerDefId)==true );
	}

	public function toggleLayer(l:LayerInstance) {
		layerVis.set(l.layerDefId, !isLayerVisible(l));
		updateLayersVisibility();
	}

	public function showLayer(l:LayerInstance) {
		layerVis.set(l.layerDefId, true);
		invalidate();
	}

	public function hideLayer(l:LayerInstance) {
		layerVis.set(l.layerDefId, false);
		invalidate();
	}

	public function renderBg() {
		// Bg
		bg.clear();
		bg.beginFill(client.project.bgColor);
		bg.drawRect(0, 0, client.curLevel.pxWid, client.curLevel.pxHei);

		// Grid
		var col = C.autoContrast(client.project.bgColor);

		grid.clear();
		if( client.curLayerInstance==null )
			return;

		var l = client.curLayerInstance;
		grid.lineStyle(1, col, 0.2);
		for( cx in 0...client.curLayerInstance.cWid+1 ) {
			grid.moveTo(cx*l.def.gridSize, 0);
			grid.lineTo(cx*l.def.gridSize, l.cHei*l.def.gridSize);
		}
		for( cy in 0...client.curLayerInstance.cHei+1 ) {
			grid.moveTo(0, cy*l.def.gridSize);
			grid.lineTo(l.cWid*l.def.gridSize, cy*l.def.gridSize);
		}
	}

	public function renderAll() {
		renderBg();
		renderLayers();
	}

	public function renderLayers() {
		for(e in layerWrappers)
			e.remove();
		layerWrappers = new Map();

		for(ld in client.project.defs.layers) {
			var li = client.curLevel.getLayerInstance(ld);
			var wrapper = new h2d.Object();
			root.add(wrapper,Const.DP_MAIN);
			root.under(wrapper);
			layerWrappers.set(li.layerDefId, wrapper);

			if( !isLayerVisible(li) )
				continue;

			var grid = li.def.gridSize;
			switch li.def.type {
				case IntGrid:
					var g = new h2d.Graphics(wrapper);
					for(cy in 0...li.cHei)
					for(cx in 0...li.cWid) {
						var id = li.getIntGrid(cx,cy);
						if( id<0 )
							continue;

						g.beginFill( li.getIntGridColorAt(cx,cy) );
						g.drawRect(cx*grid, cy*grid, grid, grid);
					}

				case Entities:
					for(ei in li.entityInstances) {
						var o = createEntityRender(ei.def, wrapper);
						o.setPosition(ei.x, ei.y);
					}
			}
		}

		updateLayersVisibility();
	}


	public static function invalidateCaches() {
		for(tex in _entityRenderCache)
			tex.dispose();
		_entityRenderCache = new Map();
	}


	public static function createEntityRender(def:EntityDef, ?parent:h2d.Object) {
		if( !_entityRenderCache.exists(def.uid) ) {
			var g = new h2d.Graphics();
			g.beginFill(def.color);
			g.lineStyle(1, 0x0, 0.25);
			g.drawRect(0, 0, def.width, def.height);

			g.lineStyle(1, 0x0, 0.5);
			var pivotSize = 3;
			g.drawRect(
				Std.int((def.width-pivotSize)*def.pivotX),
				Std.int((def.height-pivotSize)*def.pivotY),
				pivotSize, pivotSize
			);

			var tex = new h3d.mat.Texture(def.width, def.height, [Target]);
			g.drawTo(tex);
			_entityRenderCache.set(def.uid, tex);
		}

		var bmp = new h2d.Bitmap(parent);
		bmp.tile = h2d.Tile.fromTexture( _entityRenderCache.get(def.uid) );
		bmp.tile.setCenterRatio(def.pivotX, def.pivotY);

		return bmp;
	}

	function updateLayersVisibility() {
		for(ld in client.project.defs.layers) {
			var li = client.curLevel.getLayerInstance(ld);
			var wrapper = layerWrappers.get(ld.uid);
			if( wrapper==null )
				continue;

			wrapper.visible = isLayerVisible(li);
			wrapper.alpha = li.def.displayOpacity;
			// wrapper.alpha = li.def.displayOpacity * ( li==client.curLayerInstance ? 1 : 0.25 );
		}
	}

	public function onCurrentLayerChange(cur:LayerInstance) { // TODO use global event
		updateLayersVisibility();
		renderBg();
	}


	public inline function invalidate() {
		invalidated = true;
	}

	override function postUpdate() {
		super.postUpdate();

		root.setScale(zoom);
		root.x = w()*0.5 - focusLevelX * zoom;
		root.y = h()*0.5 - focusLevelY * zoom;

		if( invalidated ) {
			invalidated = false;
			renderAll();
		}
	}

}
