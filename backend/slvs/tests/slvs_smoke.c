/* app_smoke.c — proves libslvs supports exactly what iPadProCAD needs:
 * a rectangle whose skewed corners are forced true by Horizontal/Vertical,
 * a driving width dimension, a point-on-line, plus result + DOF readout
 * (DOF is what drives the white/violet "fully constrained" colouring). */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "slvs.h"

static Slvs_System sys;
static double P(int h){ int i; for(i=0;i<sys.params;i++) if(sys.param[i].h==(Slvs_hParam)h) return sys.param[i].val; return 0; }

int main(void){
    sys.param      = calloc(200,sizeof(sys.param[0]));
    sys.entity     = calloc(200,sizeof(sys.entity[0]));
    sys.constraint = calloc(200,sizeof(sys.constraint[0]));
    sys.failed     = calloc(200,sizeof(sys.failed[0]));

    Slvs_hGroup g=1; double qw,qx,qy,qz;
    /* locked workplane on the XY plane (group 1) */
    sys.param[sys.params++]=Slvs_MakeParam(1,g,0.0);
    sys.param[sys.params++]=Slvs_MakeParam(2,g,0.0);
    sys.param[sys.params++]=Slvs_MakeParam(3,g,0.0);
    sys.entity[sys.entities++]=Slvs_MakePoint3d(101,g,1,2,3);
    Slvs_MakeQuaternion(1,0,0, 0,1,0, &qw,&qx,&qy,&qz);
    sys.param[sys.params++]=Slvs_MakeParam(4,g,qw);
    sys.param[sys.params++]=Slvs_MakeParam(5,g,qx);
    sys.param[sys.params++]=Slvs_MakeParam(6,g,qy);
    sys.param[sys.params++]=Slvs_MakeParam(7,g,qz);
    sys.entity[sys.entities++]=Slvs_MakeNormal3d(102,g,4,5,6,7);
    sys.entity[sys.entities++]=Slvs_MakeWorkplane(200,g,101,102);

    g=2;
    /* four DELIBERATELY skewed corners (u,v) */
    sys.param[sys.params++]=Slvs_MakeParam(11,g,0.0);  sys.param[sys.params++]=Slvs_MakeParam(12,g,0.0);
    sys.entity[sys.entities++]=Slvs_MakePoint2d(301,g,200,11,12);      /* A bl */
    sys.param[sys.params++]=Slvs_MakeParam(13,g,52.0); sys.param[sys.params++]=Slvs_MakeParam(14,g,3.0);
    sys.entity[sys.entities++]=Slvs_MakePoint2d(302,g,200,13,14);      /* B br */
    sys.param[sys.params++]=Slvs_MakeParam(15,g,49.0); sys.param[sys.params++]=Slvs_MakeParam(16,g,41.0);
    sys.entity[sys.entities++]=Slvs_MakePoint2d(303,g,200,15,16);      /* C tr */
    sys.param[sys.params++]=Slvs_MakeParam(17,g,1.0);  sys.param[sys.params++]=Slvs_MakeParam(18,g,38.0);
    sys.entity[sys.entities++]=Slvs_MakePoint2d(304,g,200,17,18);      /* D tl */

    sys.entity[sys.entities++]=Slvs_MakeLineSegment(400,g,200,301,302); /* bottom */
    sys.entity[sys.entities++]=Slvs_MakeLineSegment(401,g,200,302,303); /* right  */
    sys.entity[sys.entities++]=Slvs_MakeLineSegment(402,g,200,303,304); /* top    */
    sys.entity[sys.entities++]=Slvs_MakeLineSegment(403,g,200,304,301); /* left   */

    int c=1;
    #define CON(t,va,pa,pb,ea,eb) sys.constraint[sys.constraints++]=Slvs_MakeConstraint(c++,g,(t),200,(va),(pa),(pb),(ea),(eb))
    CON(SLVS_C_HORIZONTAL,0,0,0,400,0);
    CON(SLVS_C_HORIZONTAL,0,0,0,402,0);
    CON(SLVS_C_VERTICAL,  0,0,0,401,0);
    CON(SLVS_C_VERTICAL,  0,0,0,403,0);
    /* pin corner A to the origin so we can check absolute coords */
    CON(SLVS_C_POINTS_COINCIDENT,0,301,101,0,0);
    /* driving width dimension: |A B| = 50 */
    CON(SLVS_C_PT_PT_DISTANCE,50.0,301,302,0,0);

    /* a fifth point placed OFF the top edge, constrained onto it */
    sys.param[sys.params++]=Slvs_MakeParam(30,g,20.0); sys.param[sys.params++]=Slvs_MakeParam(31,g,55.0);
    sys.entity[sys.entities++]=Slvs_MakePoint2d(305,g,200,30,31);
    CON(SLVS_C_PT_ON_LINE,0,305,0,402,0);

    sys.faileds=200;
    Slvs_Solve(&sys,2);

    const char* res[]={"OKAY","INCONSISTENT","DIDNT_CONVERGE","TOO_MANY_UNKNOWNS"};
    printf("result   = %s\n", (sys.result>=0&&sys.result<4)?res[sys.result]:"?");
    printf("dof      = %d   (Inventor: %d DOF still free -> under-constrained)\n", sys.dof, sys.dof);
    printf("faileds  = %d\n", sys.faileds);
    printf("A = (%.3f, %.3f)\n", P(11),P(12));
    printf("B = (%.3f, %.3f)   width|AB| = %.4f  (target 50)\n", P(13),P(14),
           P(13)-P(11));
    printf("C = (%.3f, %.3f)\n", P(15),P(16));
    printf("D = (%.3f, %.3f)\n", P(17),P(18));
    printf("P5 on top edge? v=%.4f  (top edge v = C/D v = %.4f)\n", P(31), P(16));
    return 0;
}
