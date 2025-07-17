package com.bitechular.glucoscope.ui.graphics

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import com.bitechular.glucoscope.preference.PreferenceModel
import com.bitechular.glucoscope.ui.components.SquareContainer

@Composable
fun ThemedConnectionTypeGraphic(modifier: Modifier = Modifier) {
    val prefs = PreferenceModel.current

    SquareContainer(modifier) {
        ConnectionTypeGraphic(
            dropFill = prefs.theme.lowColor,
            cloudFill = prefs.theme.text,
            lineStroke = prefs.theme.accent,
            toggleStroke = prefs.theme.surface,
            toggleSelector = prefs.theme.accent,
        )
    }
}

@Composable
fun ConnectionTypeGraphic(
    dropFill: Color = Color.Red,
    cloudFill: Color = Color.White,
    lineStroke: Color = Color.White,
    toggleStroke: Color = Color.Gray,
    toggleSelector: Color = Color.Magenta,
) {
    Canvas(modifier = Modifier.fillMaxSize()) {
        val w = size.width
        val h = size.height
        val strokePx = (minOf(w, h) * 0.05f)

        // Drop fill
        drawPath(
            path = dropPath(w, h),
            color = dropFill
        )
        // Drop shading
        drawPath(
            path = dropPath(w, h),
            brush = Brush.linearGradient(
                colors = listOf(Color.Black.copy(alpha = 0f), Color.Black.copy(alpha = 0.5f)),
                start = Offset(x = 0.5f * w, y = ConnectionTypeDrop.top * h),
                end = Offset(x = 0.5f * w, y = ConnectionTypeDrop.bottom * h)
            )
        )
        // Drop stroke
        drawPath(
            path = dropPath(w, h),
            color = toggleStroke,
            style = Stroke(width = strokePx * 0.5f, cap = StrokeCap.Round, join = StrokeJoin.Round)
        )
        // Drop stroke overlay gradient
        drawPath(
            path = dropPath(w, h),
            brush = Brush.linearGradient(
                colors = listOf(Color.Black.copy(alpha = 0f), Color.Black.copy(alpha = 0.5f)),
                start = Offset(x = 0.5f * w, y = ConnectionTypeDrop.top * h),
                end = Offset(x = 0.5f * w, y = ConnectionTypeDrop.bottom * h)
            ),
            style = Stroke(width = strokePx * 0.5f, cap = StrokeCap.Round, join = StrokeJoin.Round)
        )

        // Cloud fill
        drawPath(
            path = cloudPath(w, h),
            color = cloudFill
        )
        // Cloud shading
        drawPath(
            path = cloudPath(w, h),
            brush = Brush.linearGradient(
                colors = listOf(Color.Black.copy(alpha = 0f), Color.Black.copy(alpha = 0.15f)),
                start = Offset(x = 0.5f * w, y = (ConnectionTypeCloud.top + 0.1f) * h),
                end = Offset(x = 0.5f * w, y = ConnectionTypeCloud.bottom * h)
            )
        )
        // Cloud stroke
        drawPath(
            path = cloudPath(w, h),
            color = toggleStroke,
            style = Stroke(width = strokePx * 0.5f, cap = StrokeCap.Round)
        )

        // Lines
        drawPath(
            path = lineTopPath(w, h),
            color = lineStroke,
            style = Stroke(width = strokePx, cap = StrokeCap.Round)
        )
        drawPath(
            path = lineBottomPath(w, h),
            color = lineStroke,
            style = Stroke(width = strokePx, cap = StrokeCap.Round)
        )

        // Toggle
        drawToggle(w, h, toggleStroke, toggleSelector, strokePx)
    }
}

private object ConnectionTypeDrop {
    const val top = 0.13473f
    const val bottom = 0.39063f
}

private fun dropPath(w: Float, h: Float): Path = Path().apply {
    moveTo(0.16504f * w, 0.29689f * h)
    cubicTo(
        0.16504f * w,
        0.25312f * h,
        0.23207f * w,
        0.16187f * h,
        0.25277f * w,
        ConnectionTypeDrop.top * h
    )
    cubicTo(
        0.25583f * w,
        0.13073f * h,
        0.26175f * w,
        0.13073f * h,
        0.26480f * w,
        ConnectionTypeDrop.top * h
    )
    cubicTo(0.28551f * w, 0.16187f * h, 0.35254f * w, 0.25312f * h, 0.35254f * w, 0.29689f * h)
    cubicTo(
        0.35254f * w,
        0.34866f * h,
        0.31057f * w,
        ConnectionTypeDrop.bottom * h,
        0.25879f * w,
        ConnectionTypeDrop.bottom * h
    )
    cubicTo(
        0.20701f * w,
        ConnectionTypeDrop.bottom * h,
        0.16504f * w,
        0.34866f * h,
        0.16504f * w,
        0.29689f * h
    )
    close()
}

private object ConnectionTypeCloud {
    const val top = 0.70441f
    const val bottom = 0.87304f
}

private fun cloudPath(w: Float, h: Float): Path = Path().apply {
    // Bottom edge
    moveTo(0.32915f * w, ConnectionTypeCloud.bottom * h)
    lineTo(0.17543f * w, ConnectionTypeCloud.bottom * h)
    // Left hump
    cubicTo(
        0.16324f * w, 0.87321f * h,
        0.15145f * w, 0.86850f * h,
        0.14245f * w, 0.85987f * h
    )
    cubicTo(
        0.13346f * w, 0.85125f * h,
        0.12793f * w, 0.83935f * h,
        0.12701f * w, 0.82660f * h
    )
    cubicTo(
        0.12701f * w, 0.82526f * h,
        0.12701f * w, 0.82392f * h,
        0.12701f * w, 0.82258f * h
    )
    cubicTo(
        0.12651f * w, 0.81203f * h,
        0.12942f * w, 0.80160f * h,
        0.13525f * w, 0.79299f * h
    )
    // Rising slope
    cubicTo(
        0.14109f * w, 0.78438f * h,
        0.14952f * w, 0.77808f * h,
        0.15919f * w, 0.77511f * h
    )
    cubicTo(
        0.15919f * w, 0.77366f * h,
        0.15919f * w, 0.77222f * h,
        0.15919f * w, 0.77087f * h
    )
    cubicTo(
        0.15954f * w, 0.75785f * h,
        0.16331f * w, 0.74518f * h,
        0.17008f * w, 0.73426f * h
    )
    // Top of cloud
    cubicTo(
        0.17686f * w, 0.72334f * h,
        0.18637f * w, 0.71458f * h,
        0.19757f * w, 0.70895f * h
    )
    cubicTo(
        0.20970f * w, 0.70330f * h,
        0.22319f * w, 0.70171f * h,
        0.23621f * w, ConnectionTypeCloud.top * h
    )
    cubicTo(
        0.24923f * w, 0.70710f * h,
        0.26114f * w, 0.71395f * h,
        0.27030f * w, 0.72402f * h
    )
    // Right bumps
    cubicTo(
        0.27656f * w, 0.73071f * h,
        0.28160f * w, 0.73854f * h,
        0.28516f * w, 0.74714f * h
    )
    cubicTo(
        0.28873f * w, 0.74403f * h,
        0.29298f * w, 0.74188f * h,
        0.29752f * w, 0.74087f * h
    )
    cubicTo(
        0.30206f * w, 0.73987f * h,
        0.30677f * w, 0.74003f * h,
        0.31124f * w, 0.74136f * h
    )
    cubicTo(
        0.31780f * w, 0.74378f * h,
        0.32351f * w, 0.74821f * h,
        0.32764f * w, 0.75408f * h
    )
    cubicTo(
        0.33176f * w, 0.75996f * h,
        0.33411f * w, 0.76699f * h,
        0.33437f * w, 0.77428f * h
    )
    cubicTo(
        0.34529f * w, 0.77624f * h,
        0.35518f * w, 0.78223f * h,
        0.36227f * w, 0.79116f * h
    )
    cubicTo(
        0.36936f * w, 0.80008f * h,
        0.37318f * w, 0.81137f * h,
        0.37304f * w, 0.82299f * h
    )
    cubicTo(
        0.37304f * w, 0.86871f * h,
        0.32964f * w, 0.87294f * h,
        0.32915f * w, ConnectionTypeCloud.bottom * h
    )
    close()
}

private fun lineTopPath(w: Float, h: Float): Path = Path().apply {
    val corner = 0.05f * w
    val start = Offset(0.50391f * w, 0.19629f * h)
    val cornerCenter = Offset(0.75391f * w - corner, 0.19629f * h + corner)
    val end = Offset(0.75391f * w, 0.32129f * h)
    moveTo(start.x, start.y)
    lineTo(cornerCenter.x, start.y)
    arcTo(
        rect = Rect(
            cornerCenter.x - corner,
            cornerCenter.y - corner,
            cornerCenter.x + corner,
            cornerCenter.y + corner
        ),
        startAngleDegrees = -90f,
        sweepAngleDegrees = 90f,
        forceMoveTo = false
    )
    lineTo(end.x, end.y)
}

private fun lineBottomPath(w: Float, h: Float): Path = Path().apply {
    val corner = 0.05f * w
    val start = Offset(0.50391f * w, 0.80371f * h)
    val cornerCenter = Offset(0.75391f * w - corner, 0.80371f * h - corner)
    val end = Offset(0.75391f * w, 0.67871f * h)
    moveTo(start.x, start.y)
    lineTo(cornerCenter.x, start.y)
    arcTo(
        rect = Rect(
            cornerCenter.x - corner,
            cornerCenter.y - corner,
            cornerCenter.x + corner,
            cornerCenter.y + corner
        ),
        startAngleDegrees = 90f,
        sweepAngleDegrees = -90f,
        forceMoveTo = false
    )
    lineTo(end.x, end.y)
}

private fun DrawScope.drawToggle(
    w: Float,
    h: Float,
    stroke: Color,
    selector: Color,
    strokePx: Float
) {
    val rectW = 0.23438f * w
    val rectH = 0.10938f * h
    val cx = 0.63086f * w + rectW / 2f
    val cy = 0.44531f * h + rectH / 2f
    // Background selector
    drawRoundRect(
        color = selector,
        topLeft = Offset(cx - rectW / 2f, cy - rectH / 2f),
        size = Size(rectW, rectH),
        cornerRadius = CornerRadius(32f, 32f)
    )
    drawRoundRect(
        brush = Brush.linearGradient(
            listOf(
                Color.Black.copy(alpha = 0.5f),
                Color.Black.copy(alpha = 0.5f)
            )
        ),
        topLeft = Offset(cx - rectW / 2f, cy - rectH / 2f),
        size = Size(rectW, rectH),
        cornerRadius = CornerRadius(32f, 32f)
    )
    // Selector knob
    val knobW = 0.10449f * w
    val knobH = 0.08594f * h
    val knobX = 0.75f * w + knobW / 2f
    val knobY = 0.45703f * h + knobH / 2f
    drawRoundRect(
        color = selector,
        topLeft = Offset(knobX - knobW / 2f, knobY - knobH / 2f),
        size = Size(knobW, knobH),
        cornerRadius = CornerRadius(96f, 96f)
    )
    // Toggle stroke
    drawRoundRect(
        color = stroke,
        topLeft = Offset(cx - rectW / 2f, cy - rectH / 2f),
        size = Size(rectW, rectH),
        cornerRadius = CornerRadius(96f, 96f),
        style = Stroke(width = strokePx * 0.75f, cap = StrokeCap.Round)
    )
}
