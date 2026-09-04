// GPXtruder core geometry path, derived directly from anoved/gpxtruder gh-pages/js/gpxtruder.js (MIT).
// UI, DOM, basemap, marker rendering and SCAD display code are intentionally excluded.
// Map style + GOOGLE projection + automatic smoothing are preserved.

function distVincenty(lat1, lon1, lat2, lon2) {
    var a = 6378137, b = 6356752.314245, f = 1/298.257223563;
    var L = (lon2-lon1) * Math.PI / 180;
    var U1 = Math.atan((1-f) * Math.tan(lat1 * Math.PI / 180));
    var U2 = Math.atan((1-f) * Math.tan(lat2 * Math.PI / 180));
    var sinU1 = Math.sin(U1), cosU1 = Math.cos(U1);
    var sinU2 = Math.sin(U2), cosU2 = Math.cos(U2);
    var lambda = L, lambdaP, iterLimit = 100;
    var sinLambda, cosLambda, sinSigma, cosSigma, sigma, sinAlpha, cosSqAlpha, cos2SigmaM, C;
    do {
        sinLambda = Math.sin(lambda); cosLambda = Math.cos(lambda);
        sinSigma = Math.sqrt((cosU2*sinLambda)*(cosU2*sinLambda) +
            (cosU1*sinU2-sinU1*cosU2*cosLambda)*(cosU1*sinU2-sinU1*cosU2*cosLambda));
        if (sinSigma===0) return 0;
        cosSigma = sinU1*sinU2 + cosU1*cosU2*cosLambda;
        sigma = Math.atan2(sinSigma, cosSigma);
        sinAlpha = cosU1*cosU2*sinLambda / sinSigma;
        cosSqAlpha = 1 - sinAlpha*sinAlpha;
        cos2SigmaM = cosSigma - 2*sinU1*sinU2/cosSqAlpha;
        if (isNaN(cos2SigmaM)) cos2SigmaM = 0;
        C = f/16*cosSqAlpha*(4+f*(4-3*cosSqAlpha));
        lambdaP = lambda;
        lambda = L + (1-C) * f * sinAlpha *
            (sigma + C*sinSigma*(cos2SigmaM + C*cosSigma*(-1+2*cos2SigmaM*cos2SigmaM)));
    } while (Math.abs(lambda-lambdaP) > 1e-12 && --iterLimit>0);
    if (iterLimit===0) return NaN;
    var uSq = cosSqAlpha * (a*a - b*b) / (b*b);
    var A = 1 + uSq/16384*(4096+uSq*(-768+uSq*(320-175*uSq)));
    var B = uSq/1024 * (256+uSq*(-128+uSq*(74-47*uSq)));
    var deltaSigma = B*sinSigma*(cos2SigmaM+B/4*(cosSigma*(-1+2*cos2SigmaM*cos2SigmaM)-
        B/6*cos2SigmaM*(-3+4*sinSigma*sinSigma)*(-3+4*cos2SigmaM*cos2SigmaM)));
    return b*A*(sigma-deltaSigma);
}

function projectGoogle(v) {
    var r = 6378137.0;
    var lon = v[0] * Math.PI / 180.0;
    var lat = Math.max(-85.0511287798066, Math.min(85.0511287798066, v[1])) * Math.PI / 180.0;
    return [r * lon, r * Math.log(Math.tan(Math.PI/4 + lat/2)), v[2]];
}

function Bounds(xyz) {
    this.minx=this.maxx=xyz[0]; this.miny=this.maxy=xyz[1]; this.minz=this.maxz=xyz[2];
}
Bounds.prototype.Update = function(xyz) {
    if (xyz[0] < this.minx) this.minx = xyz[0]; if (xyz[0] > this.maxx) this.maxx = xyz[0];
    if (xyz[1] < this.miny) this.miny = xyz[1]; if (xyz[1] > this.maxy) this.maxy = xyz[1];
    if (xyz[2] < this.minz) this.minz = xyz[2]; if (xyz[2] > this.maxz) this.maxz = xyz[2];
};
Bounds.prototype.Center = function(){ return [(this.minx+this.maxx)/2,(this.miny+this.maxy)/2]; };
function Offsets(bounds,zcut){ var xy=bounds.Center(); var zoffset=0; if(zcut===true||bounds.minz<=0) zoffset=Math.floor(bounds.minz-1); return [xy[0],xy[1],zoffset]; }
function Scale(bed,xextent,yextent){ return Math.min(bed.x/xextent,bed.y/yextent); }
function ScaleBounds(bounds,bed){ return Scale(bed,bounds.maxx-bounds.minx,bounds.maxy-bounds.miny); }
function vector_angle(a,b){ return Math.atan2(b[1]-a[1],b[0]-a[0]); }

var PathSegment = {
    points:function(a,v,z){ a.push([v[0][0],v[0][1],0]); a.push([v[1][0],v[1][1],0]); a.push([v[0][0],v[0][1],z]); a.push([v[1][0],v[1][1],z]); },
    first_face:function(a){ a.push([0,2,3]); a.push([3,1,0]); },
    last_face:function(a,s){ var i=(s-1)*4; a.push([i+2,i+1,i+3]); a.push([i+2,i+0,i+1]); },
    faces:function(a,s){ if(s===0){this.first_face(a);return;} var i=(s-1)*4;
        a.push([i+2,i+6,i+3]); a.push([i+3,i+6,i+7]);
        a.push([i+3,i+7,i+5]); a.push([i+3,i+5,i+1]);
        a.push([i+6,i+2,i+0]); a.push([i+6,i+0,i+4]);
        a.push([i+0,i+5,i+4]); a.push([i+0,i+1,i+5]); }
};

function buildGPXtruder(rawPoints, opts) {
    var options = Object.assign({buffer:1, vertical:5, bedx:90, bedy:90, base:1, zcut:true, smoothtype:0, smoothspan:0}, opts||{});
    var bed = {x:options.bedx-2*options.buffer, y:options.bedy-2*options.buffer};
    var ll=[], d=[], distance=0, smooth_total=0;
    var min_lon=rawPoints[0][0], max_lon=min_lon, min_lat=rawPoints[0][1], max_lat=min_lat;
    var lastpt=rawPoints[0], rawpoints=[lastpt], totaldist=0;
    for(var i=1;i<rawPoints.length;i++){
        var rawpt=rawPoints[i];
        if(rawpt[0]<min_lon)min_lon=rawpt[0]; if(rawpt[0]>max_lon)max_lon=rawpt[0];
        if(rawpt[1]<min_lat)min_lat=rawpt[1]; if(rawpt[1]>max_lat)max_lat=rawpt[1];
        rawpoints.push(rawpt);
        var segdist=distVincenty(lastpt[1],lastpt[0],rawpt[1],rawpt[0]); totaldist+=segdist; lastpt=rawpt;
    }
    distance=totaldist;
    var smoothing_distance=options.smoothspan;
    if(options.smoothtype===0){
        var min_geo=projectGoogle([min_lon,min_lat,0]), max_geo=projectGoogle([max_lon,max_lat,0]);
        var geo_x=max_geo[0]-min_geo[0], geo_y=max_geo[1]-min_geo[1];
        var preliminaryScale=Scale(bed,geo_x,geo_y);
        smoothing_distance=Math.floor(options.buffer/preliminaryScale);
    }
    (function distFilter(points,mindist){
        var pts=[],dst=[],total=0; pts.push(points[0]);
        for(var cur=1,pre=0;cur<points.length;cur++){
            var dist=distVincenty(points[cur][1],points[cur][0],pts[pre][1],pts[pre][0]);
            if(mindist===0||dist>=mindist){ pts.push(points[cur]); dst.push(dist); total+=dist; pre+=1; }
        }
        ll=pts; d=dst; smooth_total=total;
    })(rawpoints,smoothing_distance);

    var projected_points=[]; var cd=0; var xyz=projectGoogle(ll[0]); var bounds=new Bounds(xyz); projected_points.push(xyz);
    for(i=1;i<ll.length;i++){ cd+=d[i-1]; xyz=projectGoogle(ll[i]); bounds.Update(xyz); projected_points.push(xyz); }
    var offset=Offsets(bounds,options.zcut); var scale=ScaleBounds(bounds,bed); var zscale=scale;
    var output_points=projected_points.map(function(v){ return [scale*(v[0]-offset[0]),scale*(v[1]-offset[1]),zscale*(v[2]-offset[2])*options.vertical+options.base]; });

    function acuteAngle(angle){ return (Math.abs(angle)>Math.PI/2)&&(Math.abs(angle)<(3*Math.PI)/2); }
    function segmentAngle(i){ if(i+1===output_points.length) return segmentAngle(i-1); return vector_angle(output_points[i],output_points[i+1]); }
    function jointPoints(i,rel,avga){ var jointr=options.buffer/Math.cos(rel/2); if(Math.abs(jointr)>options.buffer*2) jointr=Math.sign(jointr)*options.buffer*2;
        var lx=output_points[i][0]+jointr*Math.cos(avga+Math.PI/2), ly=output_points[i][1]+jointr*Math.sin(avga+Math.PI/2),
            rx=output_points[i][0]+jointr*Math.cos(avga-Math.PI/2), ry=output_points[i][1]+jointr*Math.sin(avga-Math.PI/2); return [[lx,ly],[rx,ry]]; }
    var last_angle, angle, rel_angle, joint_angle, path_pts, vertices=[], faces=[], stations=[];
    for(i=0, s=0;i<output_points.length;i++){
        angle=segmentAngle(i); if(i===0) last_angle=angle; rel_angle=angle-last_angle; joint_angle=rel_angle/2+last_angle;
        if(acuteAngle(rel_angle)&&(i<output_points.length-1)&&acuteAngle(segmentAngle(i+1)-angle)) continue;
        path_pts=jointPoints(i,rel_angle,joint_angle); PathSegment.points(vertices,path_pts,output_points[i][2]); PathSegment.faces(faces,s); s=s+1;
        stations.push({left:path_pts[0],right:path_pts[1],z:output_points[i][2],raw:ll[i]}); last_angle=angle;
    }
    PathSegment.last_face(faces,s);
    var centerline=stations.map(function(st){ return [(st.left[0]+st.right[0])/2,(st.left[1]+st.right[1])/2,st.z]; });
    return {inputPoints:rawPoints.length,smoothingDistanceM:smoothing_distance,filteredPoints:ll.length,stations:stations,centerline:centerline,vertices:vertices,faces:faces,scale:scale,offset:offset,distance:distance,smoothTotal:smooth_total};
}

function gpxtruderBuildJSON(inputJSON) {
    var input=JSON.parse(inputJSON); return JSON.stringify(buildGPXtruder(input.points,input.options));
}
if (typeof module !== 'undefined') module.exports={buildGPXtruder:buildGPXtruder,gpxtruderBuildJSON:gpxtruderBuildJSON};
