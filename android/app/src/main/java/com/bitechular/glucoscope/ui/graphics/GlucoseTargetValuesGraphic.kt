package com.bitechular.glucoscope.ui.graphics

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import com.bitechular.glucoscope.preference.PreferenceModel
import com.bitechular.glucoscope.ui.components.SquareContainer

@Composable
fun ThemedGlucoseTargetGraphic(modifier: Modifier = Modifier) {
    val prefs = PreferenceModel.current
    SquareContainer() {
        GlucoseTargetValuesGraphic(prefs.theme.lowColor, prefs.theme.accent, modifier.fillMaxSize())
    }
}

@Composable
fun GlucoseTargetValuesGraphic(
    dropColor: Color,
    strokeColor: Color,
    modifier: Modifier = Modifier
) {
    Canvas(
        modifier = modifier
            .fillMaxWidth()
            .aspectRatio(1f)
    ) {
        val width = size.width
        val height = size.height
        val topY = DropTop * height
        val bottomY = DropBottom * height

        // Draw drop fill
        drawPath(
            path = buildDropPath(width, height),
            color = dropColor
        )

        // Draw drop gradient overlay
        drawPath(
            path = buildDropPath(width, height),
            brush = Brush.verticalGradient(
                colors = listOf(
                    Color.Black.copy(alpha = 0f),
                    Color.Black.copy(alpha = 0.5f)
                ),
                startY = topY,
                endY = bottomY
            )
        )

        // Compute dynamic line width
        val dynamicLineWidth = (minOf(width, height) * 0.05f)

        // Draw crosshair with round caps and joins
        drawPath(
            path = buildCrosshairPath(width, height),
            color = strokeColor,
            style = Stroke(
                width = dynamicLineWidth * 0.5f,
                cap = StrokeCap.Round,
                join = StrokeJoin.Round
            )
        )
    }
}

private const val DropTop = 0.37305f
private const val DropBottom = 0.63574f

private fun buildDropPath(width: Float, height: Float): Path {
    val path = Path()
    val topY = DropTop * height
    val bottomY = DropBottom * height

    path.moveTo(0.4043f * width, 0.53958f * height)
    path.cubicTo(
        0.4043f * width, 0.49459f * height,
        0.47299f * width, 0.40069f * height,
        0.49398f * width, topY
    )
    path.cubicTo(
        0.49703f * width, 0.36903f * height,
        0.50297f * width, 0.36903f * height,
        0.50602f * width, topY
    )
    path.cubicTo(
        0.52701f * width, 0.40069f * height,
        0.5957f * width, 0.49459f * height,
        0.5957f * width, 0.53958f * height
    )
    path.cubicTo(
        0.5957f * width, 0.59269f * height,
        0.55286f * width, bottomY,
        0.5f * width, bottomY
    )
    path.cubicTo(
        0.44714f * width, bottomY,
        0.4043f * width, 0.59269f * height,
        0.4043f * width, 0.53958f * height
    )
    path.close()
    return path
}

private fun buildCrosshairPath(width: Float, height: Float): Path {
    val path = Path()
    // Inner ellipse
    path.addOval(
        Rect(
            offset = Offset(0.24292f * width, 0.24341f * height),
            size = androidx.compose.ui.geometry.Size(
                0.51367f * width,
                0.51367f * height
            )
        )
    )
    // Outer ellipse
    path.addOval(
        Rect(
            offset = Offset(0.12573f * width, 0.12622f * height),
            size = androidx.compose.ui.geometry.Size(
                0.74805f * width,
                0.74805f * height
            )
        )
    )
    // Vertical bottom line
    path.moveTo(0.49976f * width, 0.95239f * height)
    path.lineTo(0.49976f * width, 0.7688f * height)
    // Vertical top line
    path.moveTo(0.49976f * width, 0.23267f * height)
    path.lineTo(0.49976f * width, 0.0481f * height)
    // Horizontal right line
    path.moveTo(0.9519f * width, 0.50024f * height)
    path.lineTo(0.76831f * width, 0.50024f * height)
    // Horizontal left line
    path.moveTo(0.2312f * width, 0.50024f * height)
    path.lineTo(0.04761f * width, 0.50024f * height)

    return path
}
