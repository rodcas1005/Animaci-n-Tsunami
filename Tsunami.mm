#import <Cocoa/Cocoa.h>
#include <SFML/Graphics.hpp>
#include <cmath>
#include <vector>
#include <sstream>
#include <iomanip>

const int   W  = 960;
const int   H  = 560;

const float GY       = H * 0.68f;
const float MARGIN_L = 60.f;
const float MARGIN_R = 30.f;
const float GRID_W   = W - MARGIN_L - MARGIN_R;
const float GRID_H   = GY - 30.f;
const float UNITS_X  = 30.f;
const float UNITS_Y  = 15.f;

inline float lpx(float lx){ return MARGIN_L + lx*(GRID_W/UNITS_X); }
inline float lpy(float ly){ return GY       - ly*(GRID_H/UNITS_Y); }
inline float pxl(float px){ return (px-MARGIN_L)/(GRID_W/UNITS_X); }

const float SX = 1.35f;
const float SY = 0.75f;
const float PI = 3.14159265f;

float clamp01(float t){ return t<0?0:t>1?1:t; }
float lerp(float a,float b,float t){ return a+(b-a)*clamp01(t); }
float easeO3(float t){ t=clamp01(t); return 1-(1-t)*(1-t)*(1-t); }
float easeIO(float t){ t=clamp01(t); return t<.5f?2*t*t:-1+(4-2*t)*t; }

float gt=0, pt=0, spd=1;
int   phase=0;
bool  play=false;

float waveX      = 2.f;
float waveXprev  = 2.f;   // posicion anterior para calcular velocidad
float waveAmp    = 0.f;
float waveSpeed  = 0.f;   // unidades logicas / segundo
const float SIGMA = 4.4f;

struct Building{
    float lx, lw, lh;
    int   rows, idx;
    float hitT  = -1;
    float alpha =  1;
    float carryX=  0;
    float carryY=  0;
    float tilt  =  0;
};
std::vector<Building> blds;

// tiempos de activacion hardcodeados
struct Phase{ const char* name; float dur; };
const Phase PHASES[]={
    {"Fase 1 - Ola chica",          4.0f},
    {"Fase 2 - Ola crece y avanza", 8.0f},
    {"Fase 3 - Arrastre",           6.0f},
    {"Fase 4 - Fin",                2.0f}
};
const int   NP    = 4;
const float TOTAL = 20.0f;

void resetAll(){
    gt=0;pt=0;waveX=2.f;waveXprev=2.f;waveAmp=0.f;waveSpeed=0.f;
    phase=0;play=false;spd=1;
    for(auto&b:blds){b.hitT=-1;b.alpha=1;b.carryX=b.carryY=b.tilt=0;}
}

float waveHeight(float lx){
    if(waveAmp<0.01f) return 0.f;
    float dx=lx-waveX;
    if(std::abs(dx)>SIGMA*3.f) return 0.f;
    float env=std::exp(-(dx*dx)/(2.f*SIGMA*SIGMA));
    float c=std::cos((dx/(SIGMA*2.f))*PI*0.5f); c*=c;
    return waveAmp*env*c;
}

void drawBG(sf::RenderWindow&win){
    for(int i=0;i<14;++i){
        float r=i/14.f;
        sf::RectangleShape b(sf::Vector2f(W,GY/14+2));
        b.setPosition(0,(float)(i*GY/14));
        b.setFillColor(sf::Color(
            (sf::Uint8)lerp(90,170,r),
            (sf::Uint8)lerp(175,215,r),
            (sf::Uint8)lerp(215,245,r)));
        win.draw(b);
    }
    sf::RectangleShape sand(sf::Vector2f(W,H-GY+8));
    sand.setPosition(0,GY-4);
    sand.setFillColor(sf::Color(205,180,115)); win.draw(sand);
    sf::RectangleShape shore(sf::Vector2f(W,5));
    shore.setPosition(0,GY-2);
    shore.setFillColor(sf::Color(175,155,85)); win.draw(shore);
}

void drawGrid(sf::RenderWindow&win, const sf::Font&f){
    sf::Color minor(255,255,255,30);
    sf::Color major(255,255,255,75);
    sf::Color axisC(255,255,255,200);
    for(int i=0;i<=(int)UNITS_X;++i){
        float px=lpx((float)i);
        sf::Color c=(i%5==0)?major:minor;
        sf::Vertex l[2]={{sf::Vector2f(px,30.f),c},{sf::Vector2f(px,GY),c}};
        win.draw(l,2,sf::Lines);
    }
    for(int j=0;j<=(int)UNITS_Y;++j){
        float py=lpy((float)j);
        sf::Color c=(j%5==0)?major:minor;
        sf::Vertex l[2]={{sf::Vector2f(MARGIN_L,py),c},{sf::Vector2f(W-MARGIN_R,py),c}};
        win.draw(l,2,sf::Lines);
    }
    sf::Vertex ax[2]={{sf::Vector2f(MARGIN_L,GY),axisC},{sf::Vector2f(W-MARGIN_R,GY),axisC}};
    win.draw(ax,2,sf::Lines);
    float x0=lpx(0);
    sf::Vertex ay[2]={{sf::Vector2f(x0,30.f),axisC},{sf::Vector2f(x0,GY),axisC}};
    win.draw(ay,2,sf::Lines);
    for(int i=0;i<=(int)UNITS_X;i+=5){
        sf::Text t(std::to_string(i),f,10);
        t.setFillColor(sf::Color(255,255,255,160));
        t.setPosition(lpx((float)i)-5,GY+4); win.draw(t);
    }
    for(int j=5;j<=(int)UNITS_Y;j+=5){
        sf::Text t(std::to_string(j),f,10);
        t.setFillColor(sf::Color(255,255,255,160));
        t.setPosition(MARGIN_L-26,lpy((float)j)-7); win.draw(t);
    }
}

void drawWave(sf::RenderWindow&win){
    if(waveAmp<0.02f) return;
    sf::VertexArray tri(sf::TriangleStrip), foam(sf::LineStrip);
    for(float px=MARGIN_L; px<=(float)W-MARGIN_R+20.f; px+=1.5f){
        float lx=pxl(px);
        float ly=waveHeight(lx);
        float py=lpy(ly);
        float t=clamp01((lx-(waveX-SIGMA*3.f))/(SIGMA*6.f));
        sf::Uint8 r=(sf::Uint8)lerp(5,30,t),
                  g=(sf::Uint8)lerp(100,200,t),
                  b=(sf::Uint8)lerp(150,245,t);
        sf::Uint8 a=(ly>0.02f)?225:0;
        tri.append(sf::Vertex(sf::Vector2f(px,py),sf::Color(r,g,b,a)));
        tri.append(sf::Vertex(sf::Vector2f(px,GY),sf::Color(15,100,145,(sf::Uint8)(ly>0.02f?250:0))));
        if(ly>0.1f)
            foam.append(sf::Vertex(sf::Vector2f(px,py),sf::Color(255,255,255,185)));
    }
    win.draw(tri);
    if(foam.getVertexCount()>1) win.draw(foam);
}

void drawBuildings(sf::RenderWindow&win, float dt){
    const sf::Uint8 BR[][3]={
        {180,100,60},{210,180,100},{80,120,160},
        {160,80,80},{100,160,100},{140,100,180}};

    for(auto&b:blds){
        // activar SOLO cuando la cresta de la ola llega exactamente al edificio
        if(b.hitT<0 && play && waveX >= b.lx && waveAmp >= 4.0f)
            b.hitT = gt;

        if(b.hitT>=0){
            float elapsed = gt - b.hitT;
            // se mueve exactamente a la velocidad de la ola frame a frame
            if(play) b.carryX += waveSpeed * dt * spd;
            float wp  = clamp01(elapsed * 0.7f);
            b.carryY  = std::sin(wp*PI) * 2.8f;
            b.tilt    = std::sin(wp*PI*1.2f)*((b.idx%2==0)?0.38f:-0.33f);
            b.alpha   = std::max(0.f, 1.f - std::max(0.f,wp-0.80f)*5.f);
        }

        sf::Uint8 al=(sf::Uint8)(b.alpha*255);
        if(al<5) continue;
        float lx  = b.lx + b.carryX;
        float bpx = lpx(lx);
        float bpw = lpx(lx+b.lw)-bpx;
        float bphL= GY-lpy(b.lh);
        float bpyT= lpy(b.lh+b.carryY);
        sf::Transform tf;
        tf.translate(bpx+bpw/2,GY);
        tf.rotate(b.tilt*180.f/PI);
        tf.translate(-(bpx+bpw/2),-GY);
        sf::RenderStates rs; rs.transform=tf;
        int ci=b.idx%6;
        sf::RectangleShape body(sf::Vector2f(bpw,bphL));
        body.setPosition(bpx,bpyT);
        body.setFillColor(sf::Color(
            (sf::Uint8)(BR[ci][0]*b.alpha),
            (sf::Uint8)(BR[ci][1]*b.alpha),
            (sf::Uint8)(BR[ci][2]*b.alpha),al));
        body.setOutlineThickness(1);
        body.setOutlineColor(sf::Color(70,70,70,(sf::Uint8)(70*b.alpha)));
        win.draw(body,rs);
        int cols=std::max(1,(int)((bpw-8)/12));
        for(int row=0;row<b.rows;++row)
        for(int col=0;col<cols;++col){
            float wx2=bpx+4+col*12+2, wy=bpyT+10+row*20;
            if(wy+8<bpyT+bphL-4){
                bool lit=std::sin(b.idx*7.3f+row*3.1f+col*1.7f)>0;
                sf::RectangleShape w2(sf::Vector2f(7,9)); w2.setPosition(wx2,wy);
                w2.setFillColor(lit
                    ?sf::Color((sf::Uint8)(238*b.alpha),(sf::Uint8)(238*b.alpha),(sf::Uint8)(238*b.alpha),al)
                    :sf::Color((sf::Uint8)(28*b.alpha),(sf::Uint8)(28*b.alpha),(sf::Uint8)(28*b.alpha),al));
                win.draw(w2,rs);
            }
        }
        sf::RectangleShape ant(sf::Vector2f(3,12));
        ant.setPosition(bpx+bpw/2-1.5f,bpyT-12);
        ant.setFillColor(sf::Color(70,70,70,al)); win.draw(ant,rs);
        sf::CircleShape lt(3);
        lt.setPosition(bpx+bpw/2-3,bpyT-16);
        lt.setFillColor(sf::Color(239,68,68,al)); win.draw(lt,rs);
    }
}

void drawPanel(sf::RenderWindow&win, const sf::Font&f){
    sf::RectangleShape bg(sf::Vector2f(320,104));
    bg.setPosition(10,GY+10);
    bg.setFillColor(sf::Color(7,9,15,215));
    bg.setOutlineThickness(1);
    bg.setOutlineColor(sf::Color(34,211,238,80));
    win.draw(bg);
    float px=18, py=GY+14;
    std::ostringstream o; o<<std::fixed<<std::setprecision(2);
    auto txt=[&](const std::string&s,float x,float y,sf::Color c,unsigned sz){
        sf::Text tx(s,f,sz); tx.setFillColor(c); tx.setPosition(x,y); win.draw(tx);
    };
    txt("T(x,y) = (1.35x,  0.75y)", px,py, sf::Color(34,211,238,255),12); py+=19;
    txt("A = [ 1.35  0 ][ 0  0.75 ]", px,py, sf::Color(180,230,253,255),11); py+=18;
    float ox=std::max(0.f,waveX), oy=waveAmp;
    o<<"v = ("<<ox<<",  "<<oy<<")";
    txt(o.str(),px,py,sf::Color(255,220,100,255),11); py+=15; o.str("");
    o<<"T(v) = ("<<SX*ox<<",  "<<SY*oy<<")";
    txt(o.str(),px,py,sf::Color(140,220,160,255),11);
}

void drawBar(sf::RenderWindow&win){
    sf::RectangleShape bg(sf::Vector2f(W-20,4));
    bg.setPosition(10,(float)H-10);
    bg.setFillColor(sf::Color(255,255,255,18)); win.draw(bg);
    sf::RectangleShape fi(sf::Vector2f((W-20)*std::min(1.f,gt/TOTAL),4));
    fi.setPosition(10,(float)H-10);
    fi.setFillColor(sf::Color(34,180,220,200)); win.draw(fi);
}

void update(float dt){
    waveXprev = waveX;
    gt += dt;
    if(!play) return;
    float adt=dt*spd;
    pt+=adt/PHASES[phase].dur;
    if(pt>=1.f&&phase<NP-1){phase++;pt=0.f;}
    if(phase==NP-1&&pt>=1.f){pt=1.f;play=false;}

    float total_t = clamp01(gt/TOTAL);
    waveAmp = lerp(0.f, 9.0f, easeO3(clamp01(total_t/0.80f)));

    if(total_t<0.15f)
        waveX = lerp(2.f, 5.f, total_t/0.15f);
    else
        waveX = lerp(5.f, 38.f, easeIO((total_t-0.15f)/0.85f));

    // velocidad real de la ola en unidades logicas/segundo
    waveSpeed = (waveX - waveXprev) / dt;
}

void runApp(){
    blds={
        {13.0f,2.0f,5.5f,4,0},
        {16.0f,1.8f,8.0f,5,1},
        {18.5f,2.4f,6.5f,4,2},
        {21.5f,1.9f,9.0f,6,3},
        {24.2f,2.2f,5.0f,3,4},
        {26.8f,1.7f,7.0f,5,5}
    };
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
        win.clear(sf::Color(110,185,220));
        drawBG(win);
        if(hf) drawGrid(win,font);
        drawBuildings(win,dt);
        drawWave(win);
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
