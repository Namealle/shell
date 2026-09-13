#!/usr/bin/env python3
"""Reproducible RGBA8 source lattice and offline ridge-mean calibration.

128x128 storage, duplicated last row/column; RGB independent, alpha 255
(random alpha would premultiply/corrupt RGB on QML upload). R/G angular
periods are 32/64. Optional B uses 127 cells + its duplicate endpoint: a
128-cell period plus duplicate cannot fit 128 texels. Radial period is 127.
No Pillow colour tags, no scipy. Run from any directory; --stats writes JSON.
"""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from PIL import Image


def lattice():
    y,x,c=np.mgrid[:128,:128,:3].astype(np.uint32)
    with np.errstate(over='ignore'):
        n=x*np.uint32(0x9e3779b9)+y*np.uint32(0x85ebca6b)+c*np.uint32(0xc2b2ae35)+np.uint32(457)
        n=(n^(n>>16))*np.uint32(0x7feb352d)
        n=(n^(n>>15))*np.uint32(0x846ca68b)
        n=n^(n>>16)
    rgb=(n>>24).astype(np.uint8)
    for channel,period in enumerate([32,64,127]):
        rgb[:,:,channel]=rgb[:,np.arange(128)%period,channel]
    rgb[-1]=rgb[0]
    rgb[:,-1]=rgb[:,0]
    return np.dstack((rgb,np.full((128,128),255,dtype=np.uint8)))


def ease(x):
    x=np.clip(x,0,1)
    return x*x*x*(10+x*(-15+6*x))


def noise(data,v,angle,tau,octave,seed=457,cycles=32,sign=1,radial_scale=1):
    radial=[32,64,128][octave]*radial_scale
    angular=[32,64,127][octave]
    y=radial*v;j=np.floor(y);f=ease(y-j)
    def row(j):
        r=3+j*3.3/radial
        n=np.floor(cycles*(3/np.maximum(r,3))**1.5+.5)
        a=angular*(angle/(2*np.pi)-sign*n*tau)
        k=np.floor(a);t=ease(a-k)
        ix=np.mod(k+seed*(octave*7+3),angular).astype(int)
        iy=np.mod(j+seed*(octave*5+1),127).astype(int)
        return ((1-t)*data[iy,ix,octave]+t*data[iy,ix+1,octave])/255
    return (1-f)*row(j)+f*row(j+1)


def calibrate(data):
    # Deterministic stratified source samples, covering all material phases.
    n=1024*512;i=np.arange(n,dtype=np.float64)+.5
    v=np.mod(i*0.7548776662466927,1)
    angle=np.mod(i*0.5698402909980532,1)*2*np.pi
    tau=np.mod(i*0.4384471871911697,1)
    a=noise(data,v,angle,tau,0)
    b=noise(data,v+(a-.5)*.5/32,angle,tau,1)
    f=.67*a+.33*b
    def shape(q):
        t=np.clip((q-.38)/.38,0,1)
        return .12+2.6*(t*t*(3-2*t))**2
    means=[float(shape(a).mean()),float(shape(f).mean())]
    # Default seed's knot population, matching shader lookup precisely.
    j,k=np.mgrid[:16,:48];r=(j+457)%127;c=(k+457*3)%127
    rnd=data[r,c,:3]/255
    active=int(np.sum(rnd[:,:,2]<.03))
    return dict(samples=n,structured_mean_one=means[0],structured_mean_two=means[1],
                normalized_mean_at_detail075=float((.25+.75*shape(f)/means[1]).mean()),
                normalized_q99=float(np.quantile(shape(f)/means[1],.99)),
                knot_candidates=768,default_active_knots=active,
                angular_periods=[32,64,127],radial_period=127,
                rgba_bytes=128*128*4)


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,default=Path(__file__).resolve().parents[1]/'shaders/blackhole-noise.png')
    parser.add_argument('--stats',type=Path)
    args=parser.parse_args();data=lattice()
    Image.fromarray(data).save(args.output,compress_level=9,optimize=False)
    result=calibrate(data);result['sha256']=hashlib.sha256(args.output.read_bytes()).hexdigest();result['png_bytes']=args.output.stat().st_size
    anchors={6500:'FFF4E4',4200:'FFD18B',2800:'EC9B4B',1700:'74382B'}
    result['colour_anchors_linear']={}
    for temperature,hexcode in anchors.items():
        c=np.array([int(hexcode[i:i+2],16)/255 for i in [0,2,4]])
        result['colour_anchors_linear'][temperature]=np.where(c<=.04045,c/12.92,((c+.055)/1.055)**2.4).tolist()
    if args.stats:args.stats.write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result,indent=2))
