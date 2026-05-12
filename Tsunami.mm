#import <Cocoa/Cocoa.h>
#include <SFML/Graphics.hpp>
#include <cmath>
#include <vector>
#include <sstream>
#include <iomanip>

const int   W  = 960;
const int   H  = 520;
const float GY = H * 0.72f;
const float CX = W * 0.52f;
const float PI = 3.14159265f;

const float SX = 1.35f;
const float SY = 0.75f;

float clamp01(float t){ return t<0?0:t>1?1:t; }
float lerp(float a,float b,float t){ return a+(b-a)*clamp01(t); }
float easeIO(float t){ t=clamp01(t); return t<.5f?2*t*t:-1+(4-2*t)*t; }
float easeO3(float t){ t=clamp01(t); return 1-(1-t)*(1-t)*(1-t); }

float gt=0, pt=0, wx=90, hpt=0, spd=1;
int   phase=0;
bool  play=false;

struct Building{ float x,w,h; int rows,idx;
    float hitT=-1,alpha=1,fallX=0,fallY=0,tilt=0; };
std::vector<Building> blds;

struct Phase{ const char* name; float dur; };
const Phase PHASES[]={
    {"Fase 1 - Estado inicial",         2.0f},
    {"Fase 2 - T(x,y)=(1.35x, 0.75y)", 5.5f},
    {"Fase 3 - Ola avanza",             4.0f},
    {"Fase 4 - Colision",               4.5f},
    {"Fase 5 - Fin",                    2.5f}
};
const int   NP    = 5;
const float TOTAL = 18.5f;

void resetAll(){
    gt=0;pt=0;wx=90;hpt=0;phase=0;play=false;spd=1;
    for(auto&b:blds){b.hitT=-1;b.alpha=1;b.fallX=b.fallY=b.tilt=0;}
}

void drawBG(sf::RenderWindow&win){
    for(int i=0;i<14;++i){
        float r=i/14.f;
        sf::RectangleShape b(sf::Vector2f(W,GY/14+2));
        b.setPosition(0,i*GY/14);
        b.setFillColor(sf::Color(
            (sf::Uint8)lerp(100,175,r),
            (sf::Uint8)lerp(185,220,r),
            (sf::Uint8)lerp(245,255,r)));
        win.draw(b);
    }
    sf::RectangleShape sand(sf::Vector2f(W,H-GY+8));
    sand.setPosition(0,GY-4); sand.setFillColor(sf::Color(240,210,140)); win.draw(sand);
    sf::RectangleShape shore(sf::Vector2f(W,6));
    shore.setPosition(0,GY-2); shore.setFillColor(sf::Color(200,180,110)); win.draw(shore);
}

void drawGrid(sf::RenderWindow&win){
    float step=35.f, top=18.f, bot=GY-2.f, left=20.f, right=(float)W-20.f;
    sf::Color minor(255,255,255,40);
    sf::Color major(255,255,255,90);
    sf::Color axis (255,255,255,180);
    for(int i=0;i<=(int)((right-left)/step);++i){
        float x=left+i*step;
        sf::Color c=(i%5==0)?major:minor;
        sf::Vertex l[2]={sf::Vertex(sf::Vector2f(x,top),c),sf::Vertex(sf::Vector2f(x,bot),c)};
        win.draw(l,2,sf::Lines);
    }
    for(int j=0;j<=(int)(GY/step);++j){
        float y=GY-j*step; if(y<top)break;
        sf::Color c=(j%5==0)?major:minor;
        sf::Vertex l[2]={sf::Vertex(sf::Vector2f(left,y),c),sf::Vertex(sf::Vector2f(right,y),c)};
        win.draw(l,2,sf::Lines);
    }
    for(int k=0;k<2;++k){
        sf::Vertex l[2]={sf::Vertex(sf::Vector2f(left,GY-k),axis),sf::Vertex(sf::Vector2f(right,GY-k),axis)};
        win.draw(l,2,sf::Lines);
    }
    float yp=left+5*step;
    for(int k=0;k<2;++k){
        sf::Vertex l[2]={sf::Vertex(sf::Vector2f(yp+k,top),axis),sf::Vertex(sf::Vector2f(yp+k,bot),axis)};
        win.draw(l,2,sf::Lines);
    }
}

float phaseAmp(){
    if(phase==0) return lerp(0.01f, 0.08f, pt);
    if(phase==1) return lerp(0.08f, 1.0f, easeO3(pt));
    return 1.f;
}

void drawWave(sf::RenderWindow&win){
    float amp = 160.f * phaseAmp();
    float wl  = 480.f;
    float sx0 = std::max(0.f, wx-wl*6.f);
    sf::VertexArray tri(sf::TriangleStrip), foam(sf::LineStrip);
    for(float x=sx0; x<=std::min((float)W+260.f, wx+wl*6.f); x+=2){
        float rx  = wx-x;
        float env = std::exp(-rx/(wl*1.6f));
        float s   = std::pow(std::max(0.f,std::sin((rx/wl)*PI*2+gt*2)),1.5f);
        float y   = GY - amp*env*s;
        float rt  = (x-sx0)/(wx-sx0+1);
        sf::Uint8 r=(sf::Uint8)lerp(0,30,1-rt),
                  g=(sf::Uint8)lerp(160,210,rt),
                  b=(sf::Uint8)lerp(180,240,rt);
        tri.append(sf::Vertex(sf::Vector2f(x,y),  sf::Color(r,g,b,230)));
        tri.append(sf::Vertex(sf::Vector2f(x,GY), sf::Color(30,130,160,250)));
        foam.append(sf::Vertex(sf::Vector2f(x,y), sf::Color(255,255,255,200)));
    }
    win.draw(tri);
    win.draw(foam);
}

void drawBuildings(sf::RenderWindow&win){
    const sf::Uint8 BR[][3]={
        {180,100,60},{210,180,100},{80,120,160},
        {160,80,80},{100,160,100},{140,100,180}};
    for(auto&b:blds){
        float by=GY-b.h;
        if(phase==3&&b.hitT<0&&wx>b.x+b.w*0.3f&&phaseAmp()>=0.8f) b.hitT=hpt;
        float dp=(b.hitT>=0)?std::min(1.f,(hpt-b.hitT)*1.8f):0.f;
        b.alpha=std::max(0.f,1.f-dp*0.85f);
        b.tilt=dp*((b.idx%2==0)?0.38f:-0.33f);
        b.fallY=dp*dp*195; b.fallX=dp*((b.idx%2==0)?58.f:-42.f);
        sf::Uint8 al=(sf::Uint8)(b.alpha*255); if(al<5)continue;
        sf::Transform tf,tr;
        tf.translate(b.x+b.w/2,by+b.h); tf.rotate(b.tilt*180/PI);
        tf.translate(-(b.x+b.w/2),-(by+b.h));
        tr.translate(b.fallX,b.fallY);
        sf::RenderStates rs; rs.transform=tr*tf;
        int ci=b.idx%6;
        sf::RectangleShape body(sf::Vector2f(b.w,b.h)); body.setPosition(b.x,by);
        body.setFillColor(sf::Color(
            (sf::Uint8)(BR[ci][0]*b.alpha),(sf::Uint8)(BR[ci][1]*b.alpha),
            (sf::Uint8)(BR[ci][2]*b.alpha),al));
        body.setOutlineThickness(1);
        body.setOutlineColor(sf::Color(80,80,80,(sf::Uint8)(80*b.alpha)));
        win.draw(body,rs);
        int cols=(int)((b.w-10)/13);
        for(int row=0;row<b.rows;++row)
        for(int col=0;col<cols;++col){
            float wx2=b.x+5+col*13+3, wy=by+12+row*22;
            if(wy+10<by+b.h-5){
                bool lit=std::sin(b.idx*7.3f+row*3.1f+col*1.7f)>0;
                sf::RectangleShape w2(sf::Vector2f(8,10)); w2.setPosition(wx2,wy);
                w2.setFillColor(lit
                    ?sf::Color((sf::Uint8)(245*b.alpha),(sf::Uint8)(245*b.alpha),(sf::Uint8)(245*b.alpha),al)
                    :sf::Color((sf::Uint8)(30*b.alpha),(sf::Uint8)(30*b.alpha),(sf::Uint8)(30*b.alpha),al));
                win.draw(w2,rs);
            }
        }
        sf::RectangleShape ant(sf::Vector2f(4,14)); ant.setPosition(b.x+b.w/2-2,by-14);
        ant.setFillColor(sf::Color(80,80,80,al)); win.draw(ant,rs);
        sf::CircleShape lt(3); lt.setPosition(b.x+b.w/2-3,by-18);
        lt.setFillColor(sf::Color(239,68,68,al)); win.draw(lt,rs);
    }
}

void drawPanel(sf::RenderWindow&win, const sf::Font&f){
    sf::RectangleShape bg(sf::Vector2f(300,88)); bg.setPosition(10,GY+10);
    bg.setFillColor(sf::Color(7,9,15,210));
    bg.setOutlineThickness(1); bg.setOutlineColor(sf::Color(34,211,238,80));
    win.draw(bg);
    float px=18, py=GY+15;
    std::ostringstream o; o<<std::fixed<<std::setprecision(2);
    auto txt=[&](const std::string&s,float x,float y,sf::Color c,unsigned sz){
        sf::Text tx(s,f,sz); tx.setFillColor(c); tx.setPosition(x,y); win.draw(tx);
    };
    txt("T(x,y) = (1.35x,  0.75y)",   px,py, sf::Color(34,211,238,255), 12); py+=19;
    txt("A = [ 1.35  0 ][ 0  0.75 ]", px,py, sf::Color(180,230,253,255), 11); py+=18;
    // coordenadas reales de la cresta de la ola en este instante
    float fa   = phaseAmp();
    float orig_x = wx;
    float orig_y = 160.f * fa;     
    float trans_x = SX * orig_x;
    float trans_y = SY * orig_y;      
    o<<"v=("<<(int)orig_x<<", "<<(int)orig_y<<")";
    txt(o.str(), px,py, sf::Color(255,220,100,255), 11); py+=15; o.str("");
    o<<"T(v)=("<<(int)trans_x<<", "<<(int)trans_y<<")";
    txt(o.str(), px,py, sf::Color(140,220,160,255), 11);
}

void drawBar(sf::RenderWindow&win){
    sf::RectangleShape bg(sf::Vector2f(W-20,4)); bg.setPosition(10,H-10);
    bg.setFillColor(sf::Color(255,255,255,18)); win.draw(bg);
    sf::RectangleShape fi(sf::Vector2f((W-20)*std::min(1.f,gt/TOTAL),4));
    fi.setPosition(10,H-10); fi.setFillColor(sf::Color(34,180,220,200)); win.draw(fi);
}

void update(float dt){
    gt+=dt; if(!play)return;
    float adt=dt*spd; pt+=adt/PHASES[phase].dur;
    if(pt>=1.f&&phase<NP-1){ phase++; pt=0; }
    if(phase==NP-1&&pt>=1.f){ pt=1.f; play=false; }
    if(phase==0){ wx=90; }
    if(phase==1){ wx=90; }
    if(phase==2){ wx=lerp(90,CX+15,easeO3(pt)); }
    if(phase==3){ wx=lerp(CX+15,(float)(W+80),easeIO(pt)); hpt=pt; }
}

void runApp(){
    blds={{CX+10,55,145,4,0},{CX+80,48,205,5,1},{CX+143,68,162,4,2},
          {CX+228,52,225,6,3},{CX+295,62,132,3,4},{CX+372,50,182,5,5}};
    sf::RenderWindow win(sf::VideoMode(W,H),
        "T(x,y)=(1.35x, 0.75y) - UNAM Algebra Lineal",
        sf::Style::Close|sf::Style::Titlebar);
    win.setFramerateLimit(60);
    sf::Font font;
    bool hf=font.loadFromFile("/System/Library/Fonts/Supplemental/Arial.ttf");
    if(!hf) font.loadFromFile("/System/Library/Fonts/Helvetica.ttc");
    sf::Clock clk;
    while(win.isOpen()){
        sf::Event ev;
        while(win.pollEvent(ev)){
            if(ev.type==sf::Event::Closed) win.close();
            if(ev.type==sf::Event::KeyPressed){
                if(ev.key.code==sf::Keyboard::Escape) win.close();
                if(ev.key.code==sf::Keyboard::Space)  play=!play;
                if(ev.key.code==sf::Keyboard::R)      resetAll();
                if(ev.key.code==sf::Keyboard::Up)     spd=std::min(3.f,spd+0.25f);
                if(ev.key.code==sf::Keyboard::Down)   spd=std::max(0.25f,spd-0.25f);
            }
        }
        float dt=std::min(clk.restart().asSeconds(),0.05f);
        update(dt);
        win.clear(sf::Color(135,206,235));
        drawBG(win);
        drawGrid(win);
        drawWave(win);
        drawBuildings(win);
        if(hf) drawPanel(win,font);
        drawBar(win);
        win.display();
    }
}

int main(){
    @autoreleasepool{
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        [NSApp finishLaunching];
        runApp();
    }
    return 0;
}
