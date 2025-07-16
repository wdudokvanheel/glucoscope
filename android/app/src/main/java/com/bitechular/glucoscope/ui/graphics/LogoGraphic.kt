package com.bitechular.glucoscope.ui.graphics

import android.annotation.SuppressLint
import android.graphics.BlurMaskFilter
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Paint
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.asAndroidPath
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.unit.dp
import com.bitechular.glucoscope.preference.PreferenceModel
import com.bitechular.glucoscope.ui.components.SquareContainer

@Composable
fun ThemedLogoGraphic(modifier: Modifier = Modifier) {
    val prefs = PreferenceModel.current
    SquareContainer() {
        LogoGraphic(
            modifier = modifier,
            powerLight = prefs.theme.lowColor,
            background = prefs.theme.text,
            dropFill = prefs.theme.lowColor,
            dropStroke = prefs.theme.surface,
            reflectionFill = prefs.theme.text,
            graphNodesFill = prefs.theme.text
        )
    }
}

@Composable
fun LogoGraphic(
    modifier: Modifier = Modifier,
    powerLight: Color = Color(0xFF008080),
    background: Color = Color.White,
    dropFill: Color = Color.Red,
    dropStroke: Color = Color(0xFF323C4B),
    reflectionFill: Color = Color.White,
    graphNodesFill: Color = Color.White
) {
    Box(
        modifier
            .aspectRatio(1f)
            .clip(RoundedCornerShape(16.dp))
            .background(background)
    ) {
        Box(
            Modifier
                .matchParentSize()
                .background(
                    Brush.verticalGradient(
                        0f to Color.Transparent,
                        0.65f to Color.Transparent,
                        1f to Color.Black.copy(alpha = 0.15f)
                    )
                )
        )

        BurgerMenu(
            foreground = dropStroke,
            background = background,
            modifier = Modifier.matchParentSize()
        )
        PowerLight(color = powerLight, modifier = Modifier.matchParentSize())

        Canvas(Modifier.matchParentSize()) {
            val width = size.width
            val height = size.height
            val lineWidth = (minOf(width, height) * 0.04f)

            val dropPath = dropPath(size)
            drawPath(dropPath, dropFill)
            drawPath(
                dropPath,
                brush = Brush.verticalGradient(
                    listOf(
                        Color.Black.copy(alpha = 0f),
                        Color.Black.copy(alpha = 0.5f)
                    ),
                    startY = size.height * DropTop,
                    endY = size.height * DropBottom
                )
            )
            drawPath(
                dropPath,
                color = dropStroke,
                style = Stroke(width = lineWidth, cap = StrokeCap.Round, join = StrokeJoin.Round)
            )
            drawPath(
                dropPath,
                brush = Brush.verticalGradient(
                    listOf(
                        Color.Black.copy(alpha = 0f),
                        Color.Black.copy(alpha = 0.3f)
                    ),
                    startY = size.height * DropTop,
                    endY = size.height * DropBottom
                ),
                style = Stroke(width = lineWidth, cap = StrokeCap.Round, join = StrokeJoin.Round)
            )

            drawPath(
                reflectionPath(size),
                color = reflectionFill.copy(alpha = 0.9f),
                style = Stroke(width = lineWidth * 0.75f, cap = StrokeCap.Round)
            )

            val strokeW = lineWidth * 0.75f
            val nodeRadius = size.minDimension * 0.03125f
            val shadowGrow = strokeW / 2f
            val blurRadius = nodeRadius + strokeW

            fun nodeShadowPath(grow: Float): Path = Path().apply {
                val w = size.width
                val h = size.height
                val baseD = 0.0625f
                addOval(
                    Rect(
                        Offset(0.61914f * w - grow, 0.54492f * h - grow),
                        Size(baseD * w + 2 * grow, baseD * h + 2 * grow)
                    )
                )
                addOval(
                    Rect(
                        Offset(0.35156f * w - grow, 0.65332f * h - grow),
                        Size(baseD * w + 2 * grow, baseD * h + 2 * grow)
                    )
                )
            }

            drawShadow(
                path = graphLinePath(size),
                offsetY = 8.dp.toPx(),
                blurRadius = 6.dp.toPx(),
                alpha = 0.55f,
                strokeWidth = strokeW
            )

            drawShadow(
                path = nodeShadowPath(shadowGrow),
                offsetY = 6.dp.toPx(),
                blurRadius = 12f,
                alpha = 0.55f
            )

            drawPath(
                graphLinePath(size),
                color = graphNodesFill,
                style = Stroke(width = lineWidth * 0.75f, cap = StrokeCap.Round)
            )

            drawPath(graphNodesPath(size), graphNodesFill)
            drawPath(
                graphNodesPath(size),
                color = graphNodesFill,
                style = Stroke(width = lineWidth * 0.75f, cap = StrokeCap.Round)
            )
            drawPath(
                graphNodesPath(size),
                Color.Black.copy(alpha = 0.2f),
                style = Stroke(width = lineWidth * 0.75f, cap = StrokeCap.Round)
            )
        }
    }
}

@SuppressLint("UnusedBoxWithConstraintsScope")
@Composable
private fun PowerLight(color: Color, modifier: Modifier = Modifier) {
    BoxWithConstraints(modifier) {
        val w = maxWidth.value
        val h = maxHeight.value
        val lightW = (w * 0.125f).dp
        val lightH = (h * 0.0625f).dp
        val lightX = (w * 0.08984f).dp
        val lightY = (h * 0.10547f).dp

        Box(
            Modifier
                .offset(lightX, lightY)
                .size(lightW, lightH)
                .clip(RoundedCornerShape(32.dp))
                .background(color)
                .shadow(4.dp, RoundedCornerShape(32.dp))
        ) {
            Box(
                Modifier
                    .matchParentSize()
                    .background(
                        Brush.radialGradient(
                            listOf(
                                Color.White.copy(alpha = 0.15f),
                                Color.White.copy(alpha = 0f)
                            )
                        )
                    )
            )
        }
    }
}

@SuppressLint("UnusedBoxWithConstraintsScope")
@Composable
private fun BurgerMenu(
    foreground: Color,
    background: Color,
    modifier: Modifier = Modifier
) {
    BoxWithConstraints(modifier) {
        val w = maxWidth.value
        val h = maxHeight.value
        val barW = (w * 0.125f).dp
        val barH = (h * 0.03125f).dp
        val xOff = (w * 0.78516f).dp
        val ys = listOf(
            (h * 0.10547f).dp,
            (h * 0.15918f).dp
        )

        ys.forEach { y ->
            Box(
                Modifier
                    .offset(xOff, y)
                    .size(barW, barH)
                    .clip(RoundedCornerShape(32.dp))
                    .background(foreground)
            ) {
                Box(
                    Modifier
                        .matchParentSize()
                        .background(
                            Brush.linearGradient(
                                listOf(
                                    Color.Black.copy(alpha = 0.3f),
                                    Color.Black.copy(alpha = 0f)
                                ),
                                start = Offset.Infinite,
                                end = Offset.Zero
                            )
                        )
                )
            }
        }
    }
}

private const val DropTop = 0.12971f
private const val DropBottom = 0.87891f

private fun dropPath(size: Size): Path = Path().apply {
    val w = size.width
    val h = size.height
    moveTo(0.23047f * w, 0.60986f * h)
    cubicTo(0.23047f * w, 0.47446f * h, 0.45388f * w, 0.18077f * h, 0.49353f * w, DropTop * h)
    cubicTo(0.49662f * w, 0.12574f * h, 0.5024f * w, 0.12574f * h, 0.50549f * w, DropTop * h)
    cubicTo(0.54514f * w, 0.18077f * h, 0.76855f * w, 0.47446f * h, 0.76855f * w, 0.60986f * h)
    cubicTo(0.76855f * w, 0.75845f * h, 0.6481f * w, DropBottom * h, 0.49951f * w, DropBottom * h)
    cubicTo(0.35092f * w, DropBottom * h, 0.23047f * w, 0.75845f * h, 0.23047f * w, 0.60986f * h)
    close()
}

private fun reflectionPath(size: Size): Path = Path().apply {
    val w = size.width
    val h = size.height
    moveTo(0.49365f * w, 0.21973f * h)
    cubicTo(0.49365f * w, 0.21973f * h, 0.47656f * w, 0.24365f * h, 0.46484f * w, 0.2627f * h)
    moveTo(0.34473f * w, 0.46094f * h)
    cubicTo(0.34473f * w, 0.46094f * h, 0.30322f * w, 0.53174f * h, 0.29834f * w, 0.57617f * h)
    moveTo(0.43066f * w, 0.31299f * h)
    cubicTo(0.43066f * w, 0.31299f * h, 0.39502f * w, 0.36768f * h, 0.37256f * w, 0.4082f * h)
}

private fun graphNodesPath(size: Size): Path = Path().apply {
    val w = size.width
    val h = size.height
    addOval(Rect(Offset(0.61914f * w, 0.54492f * h), Size(0.0625f * w, 0.0625f * h)))
    addOval(Rect(Offset(0.35156f * w, 0.65332f * h), Size(0.0625f * w, 0.0625f * h)))
}

private fun graphLinePath(size: Size): Path = Path().apply {
    val w = size.width
    val h = size.height
    moveTo(0.38623f * w, 0.68506f * h)
    lineTo(0.44216f * w, 0.68506f * h)
    cubicTo(0.44418f * w, 0.68506f * h, 0.44611f * w, 0.68429f * h, 0.44757f * w, 0.68289f * h)
    cubicTo(0.45818f * w, 0.67273f * h, 0.50283f * w, 0.63037f * h, 0.50928f * w, 0.63037f * h)
    cubicTo(0.5166f * w, 0.63037f * h, 0.5498f * w, 0.66846f * h, 0.55957f * w, 0.66846f * h)
    cubicTo(0.56934f * w, 0.66846f * h, 0.65f * w, 0.57666f * h, 0.65f * w, 0.57666f * h)
}

private fun DrawScope.drawShadow(
    path: Path,
    offsetY: Float,
    blurRadius: Float,
    alpha: Float,
    strokeWidth: Float? = null
) {
    val fwPaint = Paint().asFrameworkPaint().apply {
        isAntiAlias = true
        color = android.graphics.Color.argb((alpha * 255).toInt(), 0, 0, 0)
        maskFilter = BlurMaskFilter(blurRadius, BlurMaskFilter.Blur.NORMAL)
        style = if (strokeWidth == null) android.graphics.Paint.Style.FILL
        else android.graphics.Paint.Style.STROKE
        if (strokeWidth != null) {
            this.strokeWidth = strokeWidth
            strokeCap = android.graphics.Paint.Cap.ROUND
            strokeJoin = android.graphics.Paint.Join.ROUND
        }
    }

    drawIntoCanvas { canvas ->
        canvas.save()
        canvas.translate(0f, offsetY)
        canvas.nativeCanvas.drawPath(path.asAndroidPath(), fwPaint)
        canvas.restore()
    }
}
