import build123d as bd
radius, wall, height, floor = 30, 2.4, 65, 3
result=bd.Cylinder(radius,height,align=(bd.Align.CENTER,bd.Align.CENTER,bd.Align.MIN))
publish(result,'Cup outside')
result-=bd.Cylinder(radius-wall,height,align=(bd.Align.CENTER,bd.Align.CENTER,bd.Align.MIN)).translate((0,0,floor))
publish(result,'Cup cavity')
with bd.BuildSketch(bd.Plane.XZ) as handle_profile:
    with bd.BuildLine():
        bd.CenterArc((radius-2, height/2), 21, -90, 180)
        bd.Line((radius-2,height/2+21),(radius-2,height/2+15))
        bd.CenterArc((radius-2,height/2),15,90,-180)
        bd.Line((radius-2,height/2-15),(radius-2,height/2-21))
    bd.make_face()
handle=bd.extrude(handle_profile.sketch,amount=3,both=True)
result+=handle
publish(result,'Fused curved handle')
assert len(result.solids())==1
