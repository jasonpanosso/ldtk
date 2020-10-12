package led.inst;

import led.LedTypes;

class LayerInstance {
	var _project : Project;
	public var def(get,never) : led.def.LayerDef; inline function get_def() return _project.defs.getLayerDef(layerDefUid);
	public var level(get,never) : Level; function get_level() return _project.getLevel(levelId);

	public var levelId : Int;
	public var layerDefUid : Int;
	public var pxOffsetX : Int = 0;
	public var pxOffsetY : Int = 0;
	public var seed : Int;

	// Layer content
	var intGrid : Map<Int,Int> = new Map(); // <coordId, value>
	public var entityInstances : Array<EntityInstance> = [];
	public var gridTiles : Map<Int,Int> = []; // <coordId, tileId>

	/** < RuleUid, < coordId, { tiles } > > **/
	public var autoTilesCache :
		Null< Map<Int, // RuleUID
			Map<Int, // CoordID
				Array<{ tid:Int, flips:Int, x:Int, y:Int }>
			>
		> > = null;

	public var cWid(get,never) : Int; inline function get_cWid() return dn.M.ceil( ( level.pxWid-pxOffsetX ) / def.gridSize );
	public var cHei(get,never) : Int; inline function get_cHei() return dn.M.ceil( ( level.pxHei-pxOffsetY ) / def.gridSize );


	public function new(p:Project, levelId:Int, layerDefUid:Int) {
		_project = p;
		this.levelId = levelId;
		this.layerDefUid = layerDefUid;
		seed = Std.random(9999999);
	}


	@:keep public function toString() {
		return 'LayerInstance#<${def.identifier}:${def.type}>';
	}


	public function toJson() : led.Json.LayerInstanceJson {
		return {
			// Fields preceded by "__" are only exported to facilitate parsing
			__identifier: def.identifier,
			__type: Std.string(def.type),
			__cWid: cWid,
			__cHei: cHei,
			__gridSize: def.gridSize,

			levelId: levelId,
			layerDefUid: layerDefUid,
			pxOffsetX: pxOffsetX,
			pxOffsetY: pxOffsetY,

			intGrid: {
				var arr = [];
				for(e in intGrid.keyValueIterator())
					arr.push({
						coordId: e.key,
						v: e.value,
					});
				arr;
			},

			autoLayerTiles: {
				var arr = [];

				if( autoTilesCache!=null ) {
					var td = _project.defs.getTilesetDef(def.autoTilesetDefUid);
					def.iterateActiveRulesInDisplayOrder( (r)->{
						if( autoTilesCache.exists( r.uid ) ) {
							for( allTiles in autoTilesCache.get( r.uid ).keyValueIterator() )
							for( tileInfos in allTiles.value )
								arr.push({
									x: tileInfos.x,
									y: tileInfos.y,
									srcX: td.getTileSourceX(tileInfos.tid),
									srcY: td.getTileSourceY(tileInfos.tid),
									f: tileInfos.flips,
									r: r.uid,
									c: allTiles.key,
								});
						}
					});
				}
				arr;
			},

			seed: seed,

			gridTiles: {
				var td = _project.defs.getTilesetDef(def.tilesetDefUid);
				var arr = [];
				for(e in gridTiles.keyValueIterator())
					if( e.value!=null )
						arr.push({
							coordId: e.key,
							tileId: e.value,
							__x: getCx(e.key) * def.gridSize,
							__y: getCy(e.key) * def.gridSize,
							__srcX: td==null ? -1 : td.getTileSourceX(e.value),
							__srcY: td==null ? -1 : td.getTileSourceY(e.value),
						});
				arr;
			},

			entityInstances: entityInstances.map( function(ei) return ei.toJson(this) ),
		}
	}

	public inline function getRuleStampRenderInfos(rule:led.def.AutoLayerRuleDef, td:led.def.TilesetDef, tileIds:Array<Int>, flipBits:Int)
	: Map<Int, { xOff:Int, yOff:Int }> {
		if( td==null )
			return null;

		// Get stamp bounds in tileset
		var top = 99999;
		var left = 99999;
		var right = 0;
		var bottom = 0;
		for(tid in tileIds) {
			top = dn.M.imin( top, td.getTileCy(tid) );
			bottom = dn.M.imax( bottom, td.getTileCy(tid) );
			left = dn.M.imin( left, td.getTileCx(tid) );
			right = dn.M.imax( right, td.getTileCx(tid) );
		}

		var out = new Map();
		for( tid in tileIds )
			out.set( tid, {
				xOff: Std.int( ( td.getTileCx(tid)-left - rule.pivotX*(right-left) + def.tilePivotX ) * def.gridSize ) * (dn.M.hasBit(flipBits,0)?-1:1),
				yOff: Std.int( ( td.getTileCy(tid)-top - rule.pivotY*(bottom-top) + def.tilePivotY ) * def.gridSize ) * (dn.M.hasBit(flipBits,1)?-1:1)
			});
		return out;
	}


	public function isEmpty() {
		switch def.type {
			case IntGrid:
				for(e in intGrid)
					return false;
				return true;

			case AutoLayer:
				for(rg in def.autoRuleGroups)
				for(r in rg.rules)
					return false;
				return false;

			case Entities:
				return entityInstances.length==0;

			case Tiles:
				for(e in gridTiles)
					return false;
				return true;
		}
	}

	public static function fromJson(p:Project, json:led.Json.LayerInstanceJson) {
		var li = new led.inst.LayerInstance( p, JsonTools.readInt(json.levelId), JsonTools.readInt(json.layerDefUid) );

		for( intGridJson in JsonTools.readArray(json.intGrid) )
			li.intGrid.set( intGridJson.coordId, intGridJson.v );

		for( gridTilesJson in JsonTools.readArray(json.gridTiles) )
			if( gridTilesJson.tileId!=null )
				li.gridTiles.set(
					JsonTools.readInt(gridTilesJson.coordId),
					JsonTools.readInt(gridTilesJson.tileId)
				);

		for( entityJson in JsonTools.readArray(json.entityInstances) )
			li.entityInstances.push( EntityInstance.fromJson(p, entityJson) );

		if( json.autoLayerTiles!=null ) {
			var jsonAutoTiles = JsonTools.readArray(json.autoLayerTiles);
			if( li.autoTilesCache==null )
				li.autoTilesCache = new Map();

			for(at in jsonAutoTiles) {
				if( !li.autoTilesCache.exists(at.r) )
					li.autoTilesCache.set(at.r, new Map());

				if( !li.autoTilesCache.get(at.r).exists(at.c) )
					li.autoTilesCache.get(at.r).set(at.c, []);

				li.autoTilesCache.get(at.r).get(at.c).push({
					tid: at.t,
					x: at.x,
					y: at.y,
					flips: at.f,
				});
			}
		}

		// if( json.autoTiles!=null ) {
			// var jsonAutoTiles = JsonTools.readArray(json.autoTiles);
			// for(ruleTiles in jsonAutoTiles) {
			// 	li.autoTilesCache.set(ruleTiles.ruleId, new Map());

			// 	// Hot-fix pre-0.2.2 naming
			// 	if( ruleTiles.results==null )
			// 		ruleTiles.results = ruleTiles.tiles;

			// 	for( jsonTileResult in JsonTools.readArray(ruleTiles.results) ) {
			// 		if( jsonTileResult.tiles!=null ) {
			// 			var jsonTiles = JsonTools.readArray(jsonTileResult.tiles);
			// 			li.autoTilesCache.get(ruleTiles.ruleId).set(
			// 				JsonTools.readInt(jsonTileResult.coordId),
			// 				{
			// 					tileIds: jsonTiles.map( (j)->j.tileId ),
			// 					flips: JsonTools.readInt(jsonTileResult.flips, 0),
			// 				}
			// 			);
			// 		}
			// 		else {
			// 			// Support for pre-0.2.2 format
			// 			li.autoTilesCache.get(ruleTiles.ruleId).set(
			// 				JsonTools.readInt(jsonTileResult.coordId),
			// 				{
			// 					tileIds: [ JsonTools.readInt(jsonTileResult.tileId) ],
			// 					flips: JsonTools.readInt(jsonTileResult.flips, 0),
			// 				}
			// 			);
			// 		}
			// 	}
			// }
		// }

		li.seed = JsonTools.readInt(json.seed, Std.random(9999999));

		li.pxOffsetX = JsonTools.readInt(json.pxOffsetX, 0);
		li.pxOffsetY = JsonTools.readInt(json.pxOffsetY, 0);

		return li;
	}

	inline function requireType(t:LayerType) {
		if( def.type!=t )
			throw 'Only works on $t layer!';
	}

	public inline function isValid(cx:Int,cy:Int) {
		return cx>=0 && cx<cWid && cy>=0 && cy<cHei;
	}

	public inline function coordId(cx:Int, cy:Int) {
		return cx + cy*cWid;
	}

	public inline function getCx(coordId:Int) {
		return coordId - Std.int(coordId/cWid)*cWid;
	}

	public inline function getCy(coordId:Int) {
		return Std.int(coordId/cWid);
	}

	public inline function levelToLayerCx(levelX:Int) {
		return Std.int( ( levelX - pxOffsetX ) / def.gridSize );
	}

	public inline function levelToLayerCy(levelY:Int) {
		return Std.int( ( levelY - pxOffsetY ) / def.gridSize );
	}

	public function tidy(p:Project) {
		_project = p;

		switch def.type {
			case IntGrid, AutoLayer:
				// Remove lost intGrid values
				if( def.type==IntGrid )
					for(cy in 0...cHei)
					for(cx in 0...cWid)
						if( getIntGrid(cx,cy) >= def.countIntGridValues() )
							removeIntGrid(cx,cy);

				if( def.isAutoLayer() && autoTilesCache!=null ) {
					// Discard lost rules autoTiles
					for( rUid in autoTilesCache.keys() )
						if( !def.hasRule(rUid) )
							autoTilesCache.remove(rUid);

					// Fix missing autoTiles
					// for(rg in def.autoRuleGroups)
					// for(r in rg.rules)
					// 	if( !autoTilesNewCache.exists(r.uid) )
					// 		applyAutoLayerRule(r);
				}

			case Entities:
				// Remove lost entities (def removed)
				var i = 0;
				while( i<entityInstances.length ) {
					if( entityInstances[i].def==null )
						entityInstances.splice(i,1);
					else
						i++;
				}

				// Cleanup field instances
				for(ei in entityInstances)
					ei.tidy(_project);

			case Tiles:
				// Lost tileset
				if( _project.defs.getTilesetDef(def.tilesetDefUid)==null )
					def.tilesetDefUid = null;
		}
	}


	@:allow(led.Level)
	function applyNewBounds(newPxLeft:Int, newPxTop:Int, newPxWid:Int, newPxHei:Int) {
		var totalOffsetX = pxOffsetX - newPxLeft;
		var totalOffsetY = pxOffsetY - newPxTop;
		var newPxOffsetX = totalOffsetX % def.gridSize;
		var newPxOffsetY = totalOffsetY % def.gridSize;
		var newCWid = dn.M.ceil( (newPxWid-newPxOffsetX) / def.gridSize );
		var newCHei = dn.M.ceil( (newPxHei-newPxOffsetY) / def.gridSize );

		// Move data
		var cDeltaX = Std.int( totalOffsetX / def.gridSize);
		var cDeltaY = Std.int( totalOffsetY / def.gridSize);
		switch def.type {
			case IntGrid:
				// Remap coords
				var old = intGrid;
				intGrid = new Map();
				for(cx in 0...cWid)
				for(cy in 0...cHei) {
					var newCx = cx + cDeltaX;
					var newCy = cy + cDeltaY;
					var newCoordId = newCx + newCy * newCWid;
					if( old.exists(coordId(cx,cy)) && newCx>=0 && newCx<newCWid && newCy>=0 && newCy<newCHei )
						intGrid.set( newCoordId, old.get(coordId(cx,cy)) );
				}

			case AutoLayer:

			case Entities:
				var i = 0;
				while( i<entityInstances.length ) {
					var ei = entityInstances[i];
					ei.x += cDeltaX*def.gridSize;
					ei.y += cDeltaY*def.gridSize;

					// Move points
					for(fi in ei.fieldInstances)
						if( fi.def.type==F_Point )
							for(i in 0...fi.getArrayLength())  {
								var pt = fi.getPointGrid(i);
								if( pt==null )
									continue;
								pt.cx+=cDeltaX;
								pt.cy+=cDeltaY;
								fi.parseValue( i, pt.cx + Const.POINT_SEPARATOR + pt.cy );
							}

					if( ei.x<0 || ei.y<0 )
						entityInstances.splice(i,1);
					else
						i++;
				}

			case Tiles:
				// Remap coords
				var old = gridTiles;
				gridTiles = new Map();
				for(cx in 0...cWid)
				for(cy in 0...cHei) {
					var newCx = cx + cDeltaX;
					var newCy = cy + cDeltaY;
					var newCoordId = newCx + newCy * newCWid;
					if( old.exists(coordId(cx,cy)) && newCx>=0 && newCx<newCWid && newCy>=0 && newCy<newCHei )
						gridTiles.set( newCoordId, old.get(coordId(cx,cy)) );
				}

		}

		// The remaining pixels are stored in offsets
		pxOffsetX = newPxOffsetX;
		pxOffsetY = newPxOffsetY;
	}

	public inline function hasAnyGridValue(cx:Int, cy:Int) {
		return switch def.type {
			case IntGrid: hasIntGrid(cx,cy);
			case Tiles: hasGridTile(cx,cy);
			case Entities: false;
			case AutoLayer: false;
		}
	}


	/** INT GRID *******************/

	public inline function getIntGrid(cx:Int, cy:Int) : Int {
		requireType(IntGrid);
		return !isValid(cx,cy) || !intGrid.exists( coordId(cx,cy) ) ? -1 : intGrid.get( coordId(cx,cy) );
	}

	public inline function getIntGridColorAt(cx:Int, cy:Int) : Null<UInt> {
		var v = def.getIntGridValueDef( getIntGrid(cx,cy) );
		return v==null ? null : v.color;
	}

	public inline function getIntGridIdentifierAt(cx:Int, cy:Int) : Null<String> {
		var v = def.getIntGridValueDef( getIntGrid(cx,cy) );
		return v==null ? null : v.identifier;
	}

	public function setIntGrid(cx:Int, cy:Int, v:Int) {
		requireType(IntGrid);
		if( isValid(cx,cy) )
			if( v>=0 )
				intGrid.set( coordId(cx,cy), v );
			else
				removeIntGrid(cx,cy);
	}

	public inline function hasIntGrid(cx:Int, cy:Int) {
		requireType(IntGrid);
		return getIntGrid(cx,cy)!=-1;
	}

	public function removeIntGrid(cx:Int, cy:Int) {
		requireType(IntGrid);
		if( isValid(cx,cy) )
			intGrid.remove( coordId(cx,cy) );
	}


	/** ENTITY INSTANCE *******************/

	public function createEntityInstance(ed:led.def.EntityDef) : Null<EntityInstance> {
		requireType(Entities);
		if( ed.maxPerLevel>0 ) {
			var all = entityInstances.filter( function(ei) return ei.defUid==ed.uid );
			switch ed.limitBehavior {
				case DiscardOldOnes:
					while( all.length>=ed.maxPerLevel )
						removeEntityInstance( all.shift() );

				case PreventAdding:
					if( all.length>=ed.maxPerLevel )
						return null;

				case MoveLastOne:
					if( all.length>=ed.maxPerLevel && all.length>0 )
						return all[ all.length-1 ];
			}
		}

		var ei = new EntityInstance(_project, ed.uid);
		entityInstances.push(ei);
		return ei;
	}

	public function duplicateEntityInstance(ei:EntityInstance) : EntityInstance {
		var copy = EntityInstance.fromJson( _project, ei.toJson(this) );
		entityInstances.push(copy);

		return copy;
	}

	public function removeEntityInstance(e:EntityInstance) {
		requireType(Entities);
		if( !entityInstances.remove(e) )
			throw "Unknown instance "+e;
	}



	/** TILES *******************/

	public function setGridTile(cx:Int, cy:Int, tileId:Null<Int>) {
		if( isValid(cx,cy) )
			if( tileId!=null )
				gridTiles.set( coordId(cx,cy), tileId );
			else
				removeGridTile(cx,cy);
	}

	public function removeGridTile(cx:Int, cy:Int) {
		if( isValid(cx,cy) )
			gridTiles.remove( coordId(cx,cy) );
	}

	public function getGridTile(cx:Int, cy:Int) : Null<Int> {
		return !isValid(cx,cy) || !gridTiles.exists( coordId(cx,cy) ) ? null : gridTiles.get( coordId(cx,cy) );
	}

	public inline function hasGridTile(cx:Int, cy:Int) : Bool {
		return getGridTile(cx,cy)!=null;
	}

	inline function applyMatchedRule(r:led.def.AutoLayerRuleDef, cx:Int, cy:Int, flips:Int) {
		var tileIds = r.tileMode==Single ? [ r.getRandomTileForCoord(seed+r.uid, cx,cy) ] : r.tileIds;
		var td = _project.defs.getTilesetDef( def.autoTilesetDefUid );
		var stampInfos = r.tileMode==Single ? null : getRuleStampRenderInfos(r, td, tileIds, flips);
		autoTilesCache.get(r.uid).set( coordId(cx,cy), tileIds.map( (tid)->{
			return {
				tid: tid,
				x: cx*def.gridSize + pxOffsetX + (stampInfos==null ? 0 : stampInfos.get(tid).xOff ),
				y: cy*def.gridSize + pxOffsetY + (stampInfos==null ? 0 : stampInfos.get(tid).yOff ),
				flips: flips,
			}
		} ) );
	}

	inline function applyAutoLayerRuleAt(source:LayerInstance, r:led.def.AutoLayerRuleDef, cx:Int, cy:Int) : Bool {
		// Init
		if( !autoTilesCache.exists(r.uid) )
			autoTilesCache.set( r.uid, [] );
		autoTilesCache.get(r.uid).remove( coordId(cx,cy) );

		// Modulos
		if( r.checker!=Vertical && cy%r.yModulo!=0 )
			return false;

		if( r.checker==Vertical && ( cy + ( Std.int(cx/r.xModulo)%2 ) )%r.yModulo!=0 )
			return false;

		if( r.checker!=Horizontal && cx%r.xModulo!=0 )
			return false;

		if( r.checker==Horizontal && ( cx + ( Std.int(cy/r.yModulo)%2 ) )%r.xModulo!=0 )
			return false;


		// Apply rule
		if( r.matches(this, source, cx,cy) ) {
			applyMatchedRule(r, cx,cy, 0);
			return true;
		}
		else if( r.flipX && r.matches(this, source, cx,cy, -1) ) {
			applyMatchedRule(r, cx,cy, 1);
			return true;
		}
		else if( r.flipY && r.matches(this, source, cx,cy, 1, -1) ) {
			applyMatchedRule(r, cx,cy, 2);
			return true;
		}
		else if( r.flipX && r.flipY && r.matches(this, source, cx,cy, -1, -1) ) {
			applyMatchedRule(r, cx,cy, 3);
			return true;
		}
		else
			return false;
	}

	public function applyAllAutoLayerRulesAt(cx:Int, cy:Int, wid:Int, hei:Int) {
		if( !def.isAutoLayer() )
			return;

		// Adjust bounds to also redraw nearby cells
		var left = dn.M.imax( 0, cx - Std.int(Const.MAX_AUTO_PATTERN_SIZE*0.5) );
		var top = dn.M.imax( 0, cy - Std.int(Const.MAX_AUTO_PATTERN_SIZE*0.5) );
		var right = dn.M.imin( cWid-1, cx + wid-1 + Std.int(Const.MAX_AUTO_PATTERN_SIZE*0.5) );
		var bottom = dn.M.imin( cHei-1, cy + hei-1 + Std.int(Const.MAX_AUTO_PATTERN_SIZE*0.5) );


		// Apply rules
		var source = def.type==IntGrid ? this : def.autoSourceLayerDefUid!=null ? level.getLayerInstance(def.autoSourceLayerDefUid) : null;
		if( source==null )
			return;

		for(cx in left...right+1)
		for(cy in top...bottom+1)
		for(rg in def.autoRuleGroups)
		for(r in rg.rules)
			applyAutoLayerRuleAt(source, r,cx,cy);
	}

	public function applyAllAutoLayerRules() {
		if( !def.isAutoLayer() )
			return;

		autoTilesCache = new Map();
		applyAllAutoLayerRulesAt(0, 0, cWid, cHei);
		App.LOG.warning("All rules applied in "+toString());
	}

	public function applyAutoLayerRule(r:led.def.AutoLayerRuleDef) {
		// TODO use cache invalidation?
		if( !def.isAutoLayer() )
			return;

		var source = def.type==IntGrid ? this : def.autoSourceLayerDefUid!=null ? level.getLayerInstance(def.autoSourceLayerDefUid) : null;
		if( source==null )
			return;

		for(cx in 0...cWid)
		for(cy in 0...cHei)
			applyAutoLayerRuleAt(source, r, cx,cy);
	}

}