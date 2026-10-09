#!/usr/bin/env python3
"""Real offline browser CAD tests: build123d + OCP.wasm, no model/provider key.

pip install playwright; playwright install chromium webkit
python tools/modelling/bundle_runtime.py
python tools/modelling/test_wasm.py --browser webkit
"""
import argparse
import asyncio
import base64
import functools
import json
import math
import threading
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from playwright.async_api import async_playwright

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / 'frontend/assets/modelling'


class Assets(SimpleHTTPRequestHandler):
    def log_message(self, *_): pass
    def end_headers(self):
        self.send_header('Content-Security-Policy', "default-src 'none'; script-src 'self' 'unsafe-eval' 'wasm-unsafe-eval'; worker-src 'self'; connect-src 'self'")
        super().end_headers()


async def suite(browser_type, url, out):
    browser = await browser_type.launch(headless=True)
    page = await browser.new_page()
    page.on('console', lambda m: print('browser:', m.type, m.text[:400], flush=True))
    page.on('pageerror', lambda e: print('page:', str(e)[:1000], flush=True))
    external = []
    async def network(route):
        if route.request.url.startswith(url): await route.continue_()
        else:
            external.append(route.request.url)
            await route.abort()
    await page.route('**/*', network)
    events = []
    await page.expose_function('cadTestEvent', lambda payload: events.append(payload))
    await page.goto(url + 'index.html')
    async def run(job):
        events.clear()
        await page.evaluate('(job)=>cadRun("test",job)', job)
        for _ in range(320):
            if events and events[-1]['event']['type'] in {'complete','error'}: break
            await asyncio.sleep(.5)
        assert events, 'No local runtime events'
        return [p['event'] for p in events]

    bracket = '''import build123d as bd
width, depth, height, bore = 40, 30, 20, 8
result = bd.Box(width,depth,height,align=(bd.Align.CENTER,bd.Align.CENTER,bd.Align.MIN))
publish(result,'Block')
result -= bd.Cylinder(bore/2,height+2,align=(bd.Align.CENTER,bd.Align.CENTER,bd.Align.MIN)).translate((0,0,-1))
publish(result,'Bore')
result = bd.fillet(result.edges().filter_by(bd.Axis.Z),radius=2)
publish(result,'Fillet')
'''
    result = await run({'part':'bracket','code':bracket,'checks':{'size_mm':[40,30,20],'solids':1}})
    assert [e['type'] for e in result] == ['preview','preview','preview','complete'], result[-1]
    assert result[-1]['problems'] == []
    assert [n['op'] for n in result[-1]['history']['nodes']]==['extrude','extrude','cut','fillet']
    expected = 40*30*20 - math.pi*4**2*20 - (4-math.pi)*2**2*20
    assert abs(result[-1]['metrics']['volume_mm3']-expected) < .001
    saved = result[-1]['step']
    if out:
        Path(out).mkdir(parents=True,exist_ok=True)
        (Path(out)/'bracket.step').write_bytes(base64.b64decode(saved))
        (Path(out)/'bracket-history.json').write_text(json.dumps(result[-1]['history'],indent=2))
    print(browser_type.name + ': bore/fillet checkpoints and exact volume passed',flush=True)

    base=await run({'code':'import build123d as bd\nresult=bd.Box(40,30,20,align=(bd.Align.CENTER,bd.Align.CENTER,bd.Align.MIN))'})
    replacement=await run({'inputs':{'Solid1':base[-1]['step']},'code':'''import build123d as bd
result=import_existing('Solid1')
result-=bd.Cylinder(4,22,align=(bd.Align.CENTER,bd.Align.CENTER,bd.Align.MIN)).translate((0,0,-1))
result=bd.fillet(result.edges().filter_by(bd.Axis.Z),radius=2)
'''})
    assert replacement[-1]['type']=='complete',replacement[-1]
    if out:
        (Path(out)/'base.step').write_bytes(base64.b64decode(base[-1]['step']))
        (Path(out)/'base-history.json').write_text(json.dumps(base[-1]['history'],indent=2))
        (Path(out)/'replace-history.json').write_text(json.dumps(replacement[-1]['history'],indent=2))

    # Uses native Y-up STEP input; import_existing converts it back to Z-up.
    revised = await run({'part':'bracket','inputs':{'Bracket':saved},
        'code':"import build123d as bd\nresult=import_existing('Bracket')\npublish(result,'Existing bracket')"})
    assert revised[-1]['type']=='complete',revised[-1]
    assert abs(revised[-1]['metrics']['bounds_mm']['min'][2])<.001
    print(browser_type.name + ': existing-solid frame round trip passed',flush=True)

    hollow = await run({'part':'Cup','code':'''import build123d as bd
outer_radius, wall, height, floor = 25, 2, 40, 3
result = bd.Cylinder(outer_radius,height,align=(bd.Align.CENTER,bd.Align.CENTER,bd.Align.MIN))
publish(result,'Cup outside')
result -= bd.Cylinder(outer_radius-wall,height,align=(bd.Align.CENTER,bd.Align.CENTER,bd.Align.MIN)).translate((0,0,floor))
publish(result,'Cup cavity')
assert len(result.solids())==1
''','checks':{'solids':1}})
    assert hollow[-1]['type']=='complete',hollow[-1]
    volume=math.pi*(25**2*40-23**2*37)
    assert abs(hollow[-1]['metrics']['volume_mm3']-volume)<.001
    print(browser_type.name + ': hollow curved cup and volume passed',flush=True)

    loft = await run({'part':'Taper','code':'''import build123d as bd
with bd.BuildPart() as model:
    with bd.BuildSketch(bd.Plane.XY): bd.Rectangle(40,30)
    with bd.BuildSketch(bd.Plane.XY.offset(40)): bd.Rectangle(20,10)
    bd.loft(ruled=True)
result=model.part
publish(result,'Tapered loft')
''','checks':{'solids':1,'size_mm':[40,30,40]}})
    assert loft[-1]['type']=='complete',loft[-1]
    assert abs(loft[-1]['metrics']['volume_mm3']-25333.3333333333)<.001
    if out:
        (Path(out)/'loft-history.json').write_text(json.dumps(loft[-1]['history'],indent=2))
    print(browser_type.name + ': builder-context loft passed',flush=True)

    text = await run({'part':'Label','code':"import build123d as bd\nresult=bd.extrude(bd.Text('CAD',12,font='Inter'),2)\npublish(result,'Embossed label')"})
    assert text[-1]['type']=='complete',text[-1]
    assert text[-1]['metrics']['volume_mm3']>0
    print(browser_type.name + ': offline text outlines and extrusion passed',flush=True)

    failed=await run({'code':"import build123d as bd\nresult=bd.Box(10,10,10)\npublish(result,'Body')\nassert False, 'deliberate feature failure'"})
    assert [e['type'] for e in failed]==['preview','error'],failed[-1]
    assert 'model.py' in failed[-1]['traceback']
    checked=await run({'code':'import build123d as bd\nresult=bd.Box(10,10,10)',
        'checks':{'size_mm':[10,10,20]}})
    assert checked[-1]['type']=='complete' and len(checked[-1]['problems'])==1
    print(browser_type.name + ': Python traceback and measured requirement failures passed',flush=True)

    # CSP and native navigation rules allow only the signed local bundle.
    cases={
        'placed-chamfer': 'result=bd.Box(30,20,10).rotate(bd.Axis.Z,30).translate((10,-5,4))\nresult=bd.chamfer(result.edges().filter_by(bd.Axis.Z),1)',
        'symmetric-straight': 'result=bd.extrude(bd.Rectangle(30,20),amount=10,both=True)',
        'symmetric-taper': 'result=bd.extrude(bd.Rectangle(30,20),amount=10,taper=5,both=True)',
        'sphere':'result=bd.Sphere(10)',
        'cone':'result=bd.Cone(15,5,20)',
        'torus':'result=bd.Torus(20,3)',
        'shell':"result=bd.Box(40,30,20)\nresult=bd.offset(result,amount=-2,openings=result.faces().sort_by(bd.Axis.Z)[-1])",
        'sweep':"profile=bd.Circle(2)\npath=bd.Edge.make_three_point_arc((0,0,0),(20,0,20),(40,0,0))\nresult=bd.sweep(profile,path)",
        'revolved-cup':'''with bd.BuildSketch(bd.Plane.XZ) as section:
    with bd.BuildLine():
        bd.Polyline((0,0),(20,0),(20,30),(18,30),(18,2),(0,2),close=True)
    bd.make_face()
result=bd.revolve(section.sketch,axis=bd.Axis.Z)''',
        'builder-cut':'''with bd.BuildPart() as model:
    with bd.BuildSketch(): bd.RectangleRounded(40,30,2)
    bd.extrude(amount=20)
    with bd.BuildSketch(bd.Plane.XY.offset(-1)): bd.Circle(4)
    bd.extrude(amount=22,mode=bd.Mode.SUBTRACT)
result=model.part''',
        # Regression for the physical iPad report: one hollow mug and a
        # curved handle, with checkpoints and editable native construction.
        'mug-with-handle':'''radius, wall, height, floor = 30, 2.4, 65, 3
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
''',
    }
    for name,code in cases.items():
        built=await run({'part':name,'code':'import build123d as bd\n'+code})
        assert built[-1]['type']=='complete',(name,built[-1])
        if out:
            (Path(out)/(name+'.step')).write_bytes(base64.b64decode(built[-1]['step']))
            (Path(out)/(name+'-history.json')).write_text(json.dumps(built[-1]['history'],indent=2))
            if name == 'mug-with-handle':
                (Path(out)/(name+'.py')).write_text('import build123d as bd\n'+code)
    if out:
        for name,built in [('loft',loft),('text',text)]:
            (Path(out)/(name+'.step')).write_bytes(base64.b64decode(built[-1]['step']))
            (Path(out)/(name+'-history.json')).write_text(json.dumps(built[-1]['history'],indent=2))
    print(browser_type.name+': editable revolves, shells, sweeps and builder histories passed',flush=True)
    unsupported=await run({'code':'import build123d as bd\nresult=bd.Solid.make_sphere(10)'})
    assert unsupported[-1]['type']=='error' and 'Unrecorded' in unsupported[-1]['error'],unsupported[-1]
    denied=await run({'code':"import js\njs.eval(\"fetch('https://example.com/blocked').catch(()=>null); undefined\")\nimport build123d as bd\nresult=bd.Box(10,10,10)"})
    assert not external, external
    # Termination must interrupt even Python that does not reach publish().
    events.clear()
    await page.evaluate('()=>cadRun("cancel",{code:"while True: pass"})')
    await asyncio.sleep(.1)
    await page.evaluate('()=>cadCancel("cancel")')
    assert events[-1]['event']['type']=='error'
    restarted=await run({'code':'import build123d as bd\nresult=bd.Box(10,10,10)'})
    assert restarted[-1]['type']=='complete',restarted[-1]
    print(browser_type.name + ': no remote requests, cancel and restart passed',flush=True)
    await browser.close()


async def main(args):
    server=ThreadingHTTPServer(('127.0.0.1',0),functools.partial(Assets,directory=str(ASSETS)))
    threading.Thread(target=server.serve_forever,daemon=True).start()
    url=f'http://127.0.0.1:{server.server_port}/'
    try:
        async with async_playwright() as browsers:
            for name in ([args.browser] if args.browser!='all' else ['chromium','webkit']):
                await suite(getattr(browsers,name),url,args.out)
    finally: server.shutdown()


if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--browser',choices=['chromium','webkit','all'],default='all')
    parser.add_argument('--out')
    asyncio.run(main(parser.parse_args()))
