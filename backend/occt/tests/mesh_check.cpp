/* What the rebuilt B-Rep gets WRONG, measured against the mesh it came from.
 *
 *   c++ -std=c++17 -O2 -I/usr/include/opencascade mesh_check.cpp -o mesh_check \
 *       -lTKernel -lTKMath -lTKG2d -lTKG3d -lTKGeomBase -lTKGeomAlgo -lTKBRep \
 *       -lTKTopAlgo -lTKShHealing -lTKService -lTKPrim -lTKMesh
 *   ./mesh_check part.stl rebuilt.brep [worst-faces-to-list]
 *
 * No pictures. Two distances, both computed against a grid over the triangles:
 *
 *   DEVIATION  every point of a built face, to the nearest input triangle.
 *              A face that is not on the model shows up here and nowhere else
 *              — this is "a face that wasn't in the STL", as a number.
 *   COVERAGE   every input triangle's centroid, to the nearest built face.
 *              A region the reconstruction dropped shows up here.
 *
 * Plus the topology facts: shells, free edges, faces built twice. */
#include <BRepTools.hxx>
#include <BRep_Builder.hxx>
#include <BRep_Tool.hxx>
#include <BRepAdaptor_Surface.hxx>
#include <BRepGProp.hxx>
#include <GProp_GProps.hxx>
#include <BRepMesh_IncrementalMesh.hxx>
#include <BRepBndLib.hxx>
#include <Bnd_Box.hxx>
#include <Poly_Triangulation.hxx>
#include <TopExp.hxx>
#include <TopExp_Explorer.hxx>
#include <TopLoc_Location.hxx>
#include <TopoDS.hxx>
#include <TopTools_IndexedDataMapOfShapeListOfShape.hxx>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <map>
#include <string>
#include <unordered_map>
#include <vector>

struct V { double x, y, z; };
static V sub(const V&a,const V&b){return {a.x-b.x,a.y-b.y,a.z-b.z};}
static double dot(const V&a,const V&b){return a.x*b.x+a.y*b.y+a.z*b.z;}
static V cross(const V&a,const V&b){return {a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x};}

/* Squared distance from p to triangle abc (Ericson, Real-Time Collision
 * Detection, 5.1.5) — exact, no iteration. */
static double distTri2(const V&p,const V&a,const V&b,const V&c)
{
    const V ab=sub(b,a), ac=sub(c,a), ap=sub(p,a);
    const double d1=dot(ab,ap), d2=dot(ac,ap);
    if(d1<=0&&d2<=0){const V d=sub(p,a);return dot(d,d);}
    const V bp=sub(p,b); const double d3=dot(ab,bp), d4=dot(ac,bp);
    if(d3>=0&&d4<=d3){const V d=sub(p,b);return dot(d,d);}
    const double vc=d1*d4-d3*d2;
    if(vc<=0&&d1>=0&&d3<=0){const double v=d1/(d1-d3);
        const V q={a.x+ab.x*v,a.y+ab.y*v,a.z+ab.z*v};const V d=sub(p,q);return dot(d,d);}
    const V cp=sub(p,c); const double d5=dot(ab,cp), d6=dot(ac,cp);
    if(d6>=0&&d5<=d6){const V d=sub(p,c);return dot(d,d);}
    const double vb=d5*d2-d1*d6;
    if(vb<=0&&d2>=0&&d6<=0){const double w=d2/(d2-d6);
        const V q={a.x+ac.x*w,a.y+ac.y*w,a.z+ac.z*w};const V d=sub(p,q);return dot(d,d);}
    const double va=d3*d6-d5*d4;
    if(va<=0&&(d4-d3)>=0&&(d5-d6)>=0){const double w=(d4-d3)/((d4-d3)+(d5-d6));
        const V q={b.x+(c.x-b.x)*w,b.y+(c.y-b.y)*w,b.z+(c.z-b.z)*w};
        const V d=sub(p,q);return dot(d,d);}
    const double den=1.0/(va+vb+vc), v=vb*den, w=vc*den;
    const V q={a.x+ab.x*v+ac.x*w,a.y+ab.y*v+ac.y*w,a.z+ab.z*v+ac.z*w};
    const V d=sub(p,q);return dot(d,d);
}

/* Uniform grid over a triangle soup, for nearest-triangle queries. */
struct Grid
{
    std::vector<V> pts;          /* 3 per triangle */
    double cell = 1;
    V lo{0,0,0};
    int nx=1, ny=1, nz=1;
    std::vector<std::vector<int>> bins;

    int idx(int i,int j,int k) const { return (k*ny+j)*nx+i; }
    void build(const std::vector<V> &tri, double diag)
    {
        pts = tri;
        V hi;
        lo = hi = pts[0];
        for (const V &p : pts) {
            lo.x=std::min(lo.x,p.x); lo.y=std::min(lo.y,p.y); lo.z=std::min(lo.z,p.z);
            hi.x=std::max(hi.x,p.x); hi.y=std::max(hi.y,p.y); hi.z=std::max(hi.z,p.z);
        }
        cell = std::max(diag / 160.0, 1e-6);
        nx = std::max(1,(int)((hi.x-lo.x)/cell)+1);
        ny = std::max(1,(int)((hi.y-lo.y)/cell)+1);
        nz = std::max(1,(int)((hi.z-lo.z)/cell)+1);
        bins.assign((size_t)nx*ny*nz, {});
        for (size_t t = 0; t < pts.size()/3; ++t) {
            V a=pts[t*3], b=pts[t*3+1], c=pts[t*3+2];
            const int i0=(int)((std::min(std::min(a.x,b.x),c.x)-lo.x)/cell);
            const int i1=(int)((std::max(std::max(a.x,b.x),c.x)-lo.x)/cell);
            const int j0=(int)((std::min(std::min(a.y,b.y),c.y)-lo.y)/cell);
            const int j1=(int)((std::max(std::max(a.y,b.y),c.y)-lo.y)/cell);
            const int k0=(int)((std::min(std::min(a.z,b.z),c.z)-lo.z)/cell);
            const int k1=(int)((std::max(std::max(a.z,b.z),c.z)-lo.z)/cell);
            for(int k=k0;k<=k1;++k)for(int j=j0;j<=j1;++j)for(int i=i0;i<=i1;++i)
                if(i>=0&&i<nx&&j>=0&&j<ny&&k>=0&&k<nz)
                    bins[idx(i,j,k)].push_back((int)t);
        }
    }
    double nearest(const V &p, double cap) const
    {
        const int ci=(int)((p.x-lo.x)/cell), cj=(int)((p.y-lo.y)/cell), ck=(int)((p.z-lo.z)/cell);
        double best = cap*cap;
        for (int ring = 0; ring <= nx+ny+nz; ++ring) {
            if (ring > 0 && best < 1e29 && std::sqrt(best) <= (ring-1)*cell)
                break;
            bool any=false;
            for(int k=ck-ring;k<=ck+ring;++k)for(int j=cj-ring;j<=cj+ring;++j)
                for(int i=ci-ring;i<=ci+ring;++i){
                    if(ring>0 && std::abs(i-ci)!=ring && std::abs(j-cj)!=ring && std::abs(k-ck)!=ring) continue;
                    if(i<0||i>=nx||j<0||j>=ny||k<0||k>=nz) continue;
                    any=true;
                    for(int t : bins[idx(i,j,k)]){
                        const double d2=distTri2(p,pts[t*3],pts[t*3+1],pts[t*3+2]);
                        if(d2<best) best=d2;
                    }
                }
            if(!any && ring>std::max(nx,std::max(ny,nz))) break;
            if(best <= 0) break;
        }
        return std::sqrt(best);
    }
};

static const char *SN(GeomAbs_SurfaceType t){switch(t){case GeomAbs_Plane:return "plane";case GeomAbs_Cylinder:return "cyl";case GeomAbs_Cone:return "cone";case GeomAbs_Sphere:return "sph";case GeomAbs_Torus:return "torus";case GeomAbs_BSplineSurface:return "bspline";default:return "other";}}

int main(int argc, char **argv)
{
    const char *stl = argc>1?argv[1]:"toka.stl";
    const char *brep = argc>2?argv[2]:"rebuilt.brep";
    const int show = argc>3?std::atoi(argv[3]):20;

    /* ---- the input mesh ---- */
    FILE *f=std::fopen(stl,"rb");
    if(!f){std::perror("stl");return 2;}
    std::fseek(f,0,SEEK_END); long len=std::ftell(f); std::fseek(f,0,SEEK_SET);
    std::vector<unsigned char> raw(len);
    if(std::fread(raw.data(),1,len,f)!=(size_t)len) return 2;
    std::fclose(f);
    unsigned nt=0; std::memcpy(&nt,&raw[80],4);
    std::vector<V> mesh; mesh.reserve(nt*3);
    V lo{1e300,1e300,1e300}, hi{-1e300,-1e300,-1e300};
    for(unsigned i=0;i<nt;++i){
        const unsigned char *rec=&raw[84+(size_t)i*50];
        float v[9]; std::memcpy(v,rec+12,36);
        for(int k=0;k<3;++k){
            V p{v[k*3],v[k*3+1],v[k*3+2]}; mesh.push_back(p);
            lo.x=std::min(lo.x,p.x);lo.y=std::min(lo.y,p.y);lo.z=std::min(lo.z,p.z);
            hi.x=std::max(hi.x,p.x);hi.y=std::max(hi.y,p.y);hi.z=std::max(hi.z,p.z);
        }
    }
    const V d=sub(hi,lo);
    const double diag=std::sqrt(dot(d,d));
    Grid gm; gm.build(mesh, diag);
    std::printf("input: %u triangles, diagonal %.3f, tolerance would be %.4f\n",
                nt, diag, diag*0.002);

    /* ---- the rebuilt shape ---- */
    TopoDS_Shape s; BRep_Builder bb;
    if(!BRepTools::Read(s,brep,bb)){std::printf("no brep\n");return 1;}
    const double defl = diag * 5e-4;
    BRepMesh_IncrementalMesh mesher(s, defl, Standard_False, 0.15, Standard_True);

    struct Row{int i,kind;double area,worst,mean;long n;double x0,y0,z0,x1,y1,z1;V at;};
    std::vector<Row> rows;
    std::vector<V> rebuilt;
    int shells=0;
    for(TopExp_Explorer sh(s,TopAbs_SHELL);sh.More();sh.Next()) shells++;
    int fi=0;
    for(TopExp_Explorer ex(s,TopAbs_FACE);ex.More();ex.Next(),++fi){
        Row r; r.i=fi; r.kind=-1; r.area=0; r.worst=0; r.mean=0; r.n=0; r.at=V{0,0,0};
        r.x0=r.y0=r.z0=r.x1=r.y1=r.z1=0;
        try{ BRepAdaptor_Surface sa(TopoDS::Face(ex.Current())); r.kind=(int)sa.GetType();
             GProp_GProps g; BRepGProp::SurfaceProperties(ex.Current(),g); r.area=g.Mass(); }
        catch(...){}
        TopLoc_Location loc;
        Handle(Poly_Triangulation) t=BRep_Tool::Triangulation(TopoDS::Face(ex.Current()),loc);
        if(!t.IsNull()){
            const gp_Trsf &tr=loc.Transformation();
            V flo{1e300,1e300,1e300}, fhi{-1e300,-1e300,-1e300};
            for(int i=1;i<=t->NbTriangles();++i){
                int a,b,c; t->Triangle(i).Get(a,b,c);
                const int id[3]={a,b,c};
                V P[3];
                for(int k=0;k<3;++k){
                    gp_Pnt q=t->Node(id[k]).Transformed(tr);
                    P[k]=V{q.X(),q.Y(),q.Z()};
                    rebuilt.push_back(P[k]);
                    flo.x=std::min(flo.x,P[k].x);flo.y=std::min(flo.y,P[k].y);flo.z=std::min(flo.z,P[k].z);
                    fhi.x=std::max(fhi.x,P[k].x);fhi.y=std::max(fhi.y,P[k].y);fhi.z=std::max(fhi.z,P[k].z);
                }
                /* sample the corners and the centroid */
                V samp[4]={P[0],P[1],P[2],
                    {(P[0].x+P[1].x+P[2].x)/3,(P[0].y+P[1].y+P[2].y)/3,(P[0].z+P[1].z+P[2].z)/3}};
                for(int k=0;k<4;++k){
                    const double dd=gm.nearest(samp[k], diag);
                    if(dd>r.worst){ r.worst=dd; r.at=samp[k]; }
                    r.mean+=dd; r.n++;
                }
            }
            r.x0=flo.x;r.y0=flo.y;r.z0=flo.z;r.x1=fhi.x;r.y1=fhi.y;r.z1=fhi.z;
        }
        if(r.n) r.mean/=r.n;
        rows.push_back(r);
    }

    TopTools_IndexedDataMapOfShapeListOfShape em;
    TopExp::MapShapesAndAncestors(s,TopAbs_EDGE,TopAbs_FACE,em);
    int freeE=0; for(int j=1;j<=em.Extent();++j) if(em(j).Extent()==1) freeE++;

    /* ---- coverage: input triangles nothing was built over ---- */
    Grid gr; double covWorst=0, covMean=0; long covN=0, covBad=0;
    if(!rebuilt.empty()){
        gr.build(rebuilt, diag);
        for(unsigned i=0;i<nt;++i){
            const V a=mesh[i*3],b=mesh[i*3+1],c=mesh[i*3+2];
            const V ctr{(a.x+b.x+c.x)/3,(a.y+b.y+c.y)/3,(a.z+b.z+c.z)/3};
            const double dd=gr.nearest(ctr, diag);
            covWorst=std::max(covWorst,dd); covMean+=dd; covN++;
            if(dd > diag*0.002) covBad++;
        }
        if(covN) covMean/=covN;
    }

    double worst=0, mean=0; long n=0;
    for(const Row&r:rows){ worst=std::max(worst,r.worst); mean+=r.mean*r.n; n+=r.n; }
    if(n) mean/=n;
    std::printf("faces %d  shells %d  free edges %d\n",(int)rows.size(),shells,freeE);
    std::printf("DEVIATION  built surface -> mesh:  max %.4f  mean %.5f  (%ld samples)\n",
                worst, mean, n);
    std::printf("COVERAGE   mesh -> built surface:  max %.4f  mean %.5f  (%ld of %u"
                " triangles further than tolerance)\n", covWorst, covMean, covBad, nt);

    std::sort(rows.begin(),rows.end(),[](const Row&a,const Row&b){return a.worst>b.worst;});
    std::printf("\nworst faces by deviation from the mesh:\n");
    for(int k=0;k<(int)rows.size()&&k<show;++k){
        const Row&r=rows[k];
        if(r.worst<=diag*0.002 && k>2) break;
        std::printf("  F%-5d %-8s A%9.3f  dev max %7.4f at (%7.3f %7.3f %7.3f) mean %7.4f"
                    "  box(%7.2f %7.2f %7.2f)-(%7.2f %7.2f %7.2f)\n",
                    r.i, r.kind<0?"BAD":SN((GeomAbs_SurfaceType)r.kind), r.area,
                    r.worst, r.at.x, r.at.y, r.at.z, r.mean, r.x0,r.y0,r.z0,r.x1,r.y1,r.z1);
    }

    /* ---- faces built twice ---- */
    std::map<std::string,std::vector<int>> dup;
    for(const Row&r:rows){
        if(r.area<=0) continue;
        char key[160];
        std::snprintf(key,sizeof key,"%d|%.4f|%.3f|%.3f|%.3f|%.3f|%.3f|%.3f",
                      r.kind,r.area,r.x0,r.y0,r.z0,r.x1,r.y1,r.z1);
        dup[key].push_back(r.i);
    }
    int dupGroups=0, dupFaces=0;
    for(std::map<std::string,std::vector<int>>::iterator it=dup.begin();it!=dup.end();++it)
        if(it->second.size()>1){ dupGroups++; dupFaces+=(int)it->second.size(); }
    std::printf("\nfaces built more than once: %d faces in %d groups\n",dupFaces,dupGroups);
    int shown=0;
    for(std::map<std::string,std::vector<int>>::iterator it=dup.begin();
        it!=dup.end()&&shown<8;++it)
        if(it->second.size()>1){
            std::printf("   x%d  %s\n",(int)it->second.size(),it->first.c_str());
            shown++;
        }
    return 0;
}
