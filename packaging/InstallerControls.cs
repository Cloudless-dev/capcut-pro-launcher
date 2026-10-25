using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

internal static class SetupStyle {
    public static readonly Color Canvas=Color.FromArgb(245,242,252),Card=Color.White,Ink=Color.FromArgb(41,37,58),Muted=Color.FromArgb(127,119,145),Accent=Color.FromArgb(119,79,204),Line=Color.FromArgb(229,222,241);
    public static GraphicsPath Rounded(RectangleF r,float radius){
        float d=Math.Min(radius*2,Math.Min(r.Width,r.Height));var p=new GraphicsPath();
        p.AddArc(r.X,r.Y,d,d,180,90);p.AddArc(r.Right-d,r.Y,d,d,270,90);p.AddArc(r.Right-d,r.Bottom-d,d,d,0,90);p.AddArc(r.X,r.Bottom-d,d,d,90,90);p.CloseFigure();return p;
    }
}
internal sealed class SetupCard:Panel {
    public SetupCard(){DoubleBuffered=true;BackColor=SetupStyle.Card;}
    protected override void OnPaint(PaintEventArgs e){
        e.Graphics.Clear(Parent==null?SetupStyle.Canvas:Parent.BackColor);e.Graphics.SmoothingMode=SmoothingMode.AntiAlias;
        using(var p=SetupStyle.Rounded(new RectangleF(1,1,Width-3,Height-3),18)){
            using(var b=new SolidBrush(SetupStyle.Card))e.Graphics.FillPath(b,p);using(var pen=new Pen(SetupStyle.Line))e.Graphics.DrawPath(pen,p);
        }
        base.OnPaint(e);
    }
}
internal sealed class SetupButton:Button {
    public bool Primary;
    bool hover;
    public SetupButton(){SetStyle(ControlStyles.UserPaint|ControlStyles.OptimizedDoubleBuffer|ControlStyles.AllPaintingInWmPaint,true);Cursor=Cursors.Hand;FlatStyle=FlatStyle.Flat;FlatAppearance.BorderSize=0;}
    protected override void OnMouseEnter(EventArgs e){hover=true;Invalidate();base.OnMouseEnter(e);}
    protected override void OnMouseLeave(EventArgs e){hover=false;Invalidate();base.OnMouseLeave(e);}
    protected override void OnGotFocus(EventArgs e){base.OnGotFocus(e);Invalidate();}
    protected override void OnLostFocus(EventArgs e){base.OnLostFocus(e);Invalidate();}
    protected override void OnPaint(PaintEventArgs e){
        e.Graphics.Clear(Parent==null?SetupStyle.Canvas:Parent.BackColor);e.Graphics.SmoothingMode=SmoothingMode.AntiAlias;
        Color fill=Primary?(hover?Color.FromArgb(63,49,88):SetupStyle.Ink):(hover?Color.FromArgb(237,231,248):SetupStyle.Card);
        Color ink=Primary?Color.White:SetupStyle.Ink;if(!Enabled){fill=Color.FromArgb(231,225,241);ink=SetupStyle.Muted;}
        using(var p=SetupStyle.Rounded(new RectangleF(1,1,Width-3,Height-3),13)){
            using(var b=new SolidBrush(fill))e.Graphics.FillPath(b,p);if(!Primary)using(var pen=new Pen(SetupStyle.Line))e.Graphics.DrawPath(pen,p);
            if(Focused&&ShowFocusCues)using(var pen=new Pen(SetupStyle.Accent,2))e.Graphics.DrawPath(pen,p);
        }
        TextRenderer.DrawText(e.Graphics,Text,Font,new Rectangle(10,0,Width-20,Height),ink,TextFormatFlags.HorizontalCenter|TextFormatFlags.VerticalCenter|TextFormatFlags.SingleLine|TextFormatFlags.EndEllipsis);
    }
}
internal sealed class SetupToggle:CheckBox {
    public SetupToggle(){SetStyle(ControlStyles.UserPaint|ControlStyles.OptimizedDoubleBuffer|ControlStyles.AllPaintingInWmPaint,true);Cursor=Cursors.Hand;}
    protected override void OnPaint(PaintEventArgs e){
        e.Graphics.Clear(BackColor);e.Graphics.SmoothingMode=SmoothingMode.AntiAlias;
        TextRenderer.DrawText(e.Graphics,Text,Font,new Rectangle(0,0,Width-66,Height),Enabled?SetupStyle.Ink:SetupStyle.Muted,TextFormatFlags.VerticalCenter|TextFormatFlags.EndEllipsis);
        int x=Width-48,y=(Height-26)/2;
        using(var shape=SetupStyle.Rounded(new RectangleF(x,y,46,26),13))using(var b=new SolidBrush(Checked?SetupStyle.Accent:SetupStyle.Line))e.Graphics.FillPath(b,shape);
        using(var b=new SolidBrush(Color.White))e.Graphics.FillEllipse(b,x+(Checked?23:3),y+3,20,20);
        if(Focused&&ShowFocusCues)ControlPaint.DrawFocusRectangle(e.Graphics,new Rectangle(0,1,Width-1,Height-2));
    }
}
internal sealed class SetupProgress:Control {
    int value;
    public int Value{get{return value;}set{this.value=Math.Max(0,Math.Min(100,value));Invalidate();}}
    public SetupProgress(){SetStyle(ControlStyles.UserPaint|ControlStyles.OptimizedDoubleBuffer|ControlStyles.AllPaintingInWmPaint,true);}
    protected override void OnPaint(PaintEventArgs e){
        e.Graphics.Clear(BackColor);e.Graphics.SmoothingMode=SmoothingMode.AntiAlias;
        var r=new RectangleF(0,0,Width,Height);
        using(var path=SetupStyle.Rounded(r,Height/2f))using(var b=new SolidBrush(SetupStyle.Line))e.Graphics.FillPath(b,path);
        if(value>0)using(var path=SetupStyle.Rounded(new RectangleF(0,0,Math.Max(Height,Width*value/100f),Height),Height/2f))using(var b=new SolidBrush(SetupStyle.Accent))e.Graphics.FillPath(b,path);
    }
}
