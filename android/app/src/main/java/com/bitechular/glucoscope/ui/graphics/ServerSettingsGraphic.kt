package com.bitechular.glucoscope.ui.graphics

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
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
fun ThemedServerSettingsGraphic(modifier: Modifier = Modifier) {
    val prefs = PreferenceModel.current
    SquareContainer() {
        ServerSettingsGraphic(
            dropFill = prefs.theme.lowColor,
            gearsFill = prefs.theme.accent,
            cloudFill = prefs.theme.text,
            modifier = modifier.fillMaxSize(),
        )
    }
}

@Composable
fun ServerSettingsGraphic(
    modifier: Modifier = Modifier,
    dropFill: Color = Color.Red,
    gearsFill: Color = Color(0xFF008080),
    cloudFill: Color = Color.White
) {
    Canvas(modifier = modifier.aspectRatio(1f)) {
        val w = size.width
        val h = size.height
        val lineWidth = (minOf(w, h) * 0.05f)

        drawPath(path = cloudPath(w, h), color = cloudFill)
        drawPath(
            path = cloudPath(w, h),
            brush = Brush.linearGradient(
                listOf(Color.Black.copy(alpha = 0f), Color.Black.copy(alpha = 0.15f)),
                start = Offset(0.5f * w, (Cloud.TOP + 0.1f) * h),
                end = Offset(0.5f * w, Cloud.BOTTOM * h)
            )
        )
        drawPath(path = dropPath(w, h), color = dropFill)
        drawPath(
            path = dropPath(w, h),
            brush = Brush.linearGradient(
                listOf(Color.Black.copy(alpha = 0f), Color.Black.copy(alpha = 0.5f)),
                start = Offset(0.5f * w, Drop.TOP * h),
                end = Offset(0.5f * w, Drop.BOTTOM * h)
            )
        )
        drawPath(
            path = gearsPath(w, h),
            color = gearsFill,
            style = Stroke(
                width = lineWidth * 0.5f,
                cap = StrokeCap.Round,
                join = StrokeJoin.Round
            )
        )
    }
}

private object Cloud {
    const val TOP = 0.51442f;
    const val BOTTOM = 0.87011f
}

private object Drop {
    const val TOP = 0.13767f;
    const val BOTTOM = 0.51172f
}

private fun cloudPath(w: Float, h: Float) = Path().apply {
    moveTo(0.82144f * w, Cloud.BOTTOM * h)
    lineTo(0.47312f * w, Cloud.BOTTOM * h)
    cubicTo(0.44550f * w, 0.87046f * h, 0.41878f * w, 0.86053f * h, 0.39840f * w, 0.84233f * h)
    cubicTo(0.37802f * w, 0.82414f * h, 0.36550f * w, 0.79904f * h, 0.36341f * w, 0.77216f * h)
    cubicTo(0.36341f * w, 0.76933f * h, 0.36341f * w, 0.76650f * h, 0.36341f * w, 0.76367f * h)
    cubicTo(0.36228f * w, 0.74141f * h, 0.36886f * w, 0.71943f * h, 0.38209f * w, 0.70127f * h)
    cubicTo(0.39532f * w, 0.68311f * h, 0.41442f * w, 0.66982f * h, 0.43633f * w, 0.66354f * h)
    cubicTo(0.43633f * w, 0.66049f * h, 0.43633f * w, 0.65744f * h, 0.43633f * w, 0.65462f * h)
    cubicTo(0.43713f * w, 0.62715f * h, 0.44567f * w, 0.60043f * h, 0.46101f * w, 0.57739f * h)
    cubicTo(0.47636f * w, 0.55435f * h, 0.49790f * w, 0.53588f * h, 0.52329f * w, 0.52401f * h)
    cubicTo(0.55077f * w, 0.51208f * h, 0.58135f * w, 0.50873f * h, 0.61085f * w, Cloud.TOP * h)
    cubicTo(0.64035f * w, 0.52011f * h, 0.66733f * w, 0.53456f * h, 0.68809f * w, 0.55579f * h)
    cubicTo(0.70227f * w, 0.56990f * h, 0.71369f * w, 0.58642f * h, 0.72176f * w, 0.60455f * h)
    cubicTo(0.72986f * w, 0.59800f * h, 0.73947f * w, 0.59346f * h, 0.74976f * w, 0.59134f * h)
    cubicTo(0.76006f * w, 0.58921f * h, 0.77073f * w, 0.58956f * h, 0.78085f * w, 0.59236f * h)
    cubicTo(0.79572f * w, 0.59746f * h, 0.80867f * w, 0.60682f * h, 0.81801f * w, 0.61920f * h)
    cubicTo(0.82736f * w, 0.63158f * h, 0.83267f * w, 0.64643f * h, 0.83326f * w, 0.66180f * h)
    cubicTo(0.85800f * w, 0.66594f * h, 0.88042f * w, 0.67856f * h, 0.89648f * w, 0.69740f * h)
    cubicTo(0.91254f * w, 0.71623f * h, 0.92120f * w, 0.74004f * h, 0.92089f * w, 0.76454f * h)
    cubicTo(0.92089f * w, 0.86097f * h, 0.82255f * w, 0.86989f * h, 0.82144f * w, Cloud.BOTTOM * h)
    close()
}

private fun dropPath(w: Float, h: Float) = Path().apply {
    moveTo(0.65039f * w, 0.37598f * h)
    cubicTo(0.65039f * w, 0.31057f * h, 0.75337f * w, 0.17194f * h, 0.77962f * w, Drop.TOP * h)
    cubicTo(0.78268f * w, 0.13367f * h, 0.78861f * w, 0.13367f * h, 0.79168f * w, Drop.TOP * h)
    cubicTo(0.81793f * w, 0.17194f * h, 0.92090f * w, 0.31057f * h, 0.92090f * w, 0.37598f * h)
    cubicTo(
        0.92090f * w,
        0.45095f * h,
        0.86034f * w,
        Drop.BOTTOM * h,
        0.78565f * w,
        Drop.BOTTOM * h
    )
    cubicTo(0.71095f * w, Drop.BOTTOM * h, 0.65039f * w, 0.45095f * h, 0.65039f * w, 0.37598f * h)
    close()
}

private fun gearsPath(w: Float, h: Float) = Path().apply {
    moveTo(0.29890f * w, 0.73207f * h)
    lineTo(0.25043f * w, 0.70732f * h)
    cubicTo(0.24174f * w, 0.70288f * h, 0.23147f * w, 0.70276f * h, 0.22267f * w, 0.70699f * h)
    lineTo(0.20761f * w, 0.71424f * h)
    cubicTo(0.19617f * w, 0.71975f * h, 0.18253f * w, 0.71778f * h, 0.17311f * w, 0.70927f * h)
    lineTo(0.14417f * w, 0.68314f * h)
    cubicTo(0.13313f * w, 0.67316f * h, 0.13065f * w, 0.65678f * h, 0.13825f * w, 0.64398f * h)
    lineTo(0.14649f * w, 0.63012f * h)
    cubicTo(0.15150f * w, 0.62169f * h, 0.15226f * w, 0.61139f * h, 0.14854f * w, 0.60232f * h)
    lineTo(0.13525f * w, 0.56984f * h)
    cubicTo(0.13129f * w, 0.56018f * h, 0.12277f * w, 0.55314f * h, 0.11254f * w, 0.55106f * h)
    lineTo(0.10688f * w, 0.54991f * h)
    cubicTo(0.09277f * w, 0.54704f * h, 0.08244f * w, 0.53491f * h, 0.08187f * w, 0.52052f * h)
    lineTo(0.08025f * w, 0.47966f * h)
    cubicTo(0.07960f * w, 0.46340f * h, 0.09165f * w, 0.44936f * h, 0.10780f * w, 0.44739f * h)
    cubicTo(0.11856f * w, 0.44608f * h, 0.12794f * w, 0.43928f * h, 0.13247f * w, 0.42943f * h)
    lineTo(0.14822f * w, 0.39521f * h)
    cubicTo(0.15216f * w, 0.38665f * h, 0.15202f * w, 0.37677f * h, 0.14785f * w, 0.36832f * h)
    lineTo(0.13922f * w, 0.35082f * h)
    cubicTo(0.13311f * w, 0.33842f * h, 0.13586f * w, 0.32349f * h, 0.14598f * w, 0.31409f * h)
    lineTo(0.16918f * w, 0.29255f * h)
    cubicTo(0.18043f * w, 0.28211f * h, 0.19758f * w, 0.28138f * h, 0.20967f * w, 0.29082f * h)
    lineTo(0.21527f * w, 0.29518f * h)
    cubicTo(0.22488f * w, 0.30268f * h, 0.23797f * w, 0.30391f * h, 0.24881f * w, 0.29833f * h)
    lineTo(0.28407f * w, 0.28016f * h)
    cubicTo(0.29119f * w, 0.27649f * h, 0.29663f * w, 0.27022f * h, 0.29927f * w, 0.26266f * h)
    lineTo(0.30654f * w, 0.24179f * h)
    cubicTo(0.31091f * w, 0.22924f * h, 0.32275f * w, 0.22082f * h, 0.33605f * w, 0.22082f * h)
    lineTo(0.36687f * w, 0.22082f * h)
    cubicTo(0.37960f * w, 0.22082f * h, 0.39107f * w, 0.22855f * h, 0.39584f * w, 0.24035f * h)
    lineTo(0.40370f * w, 0.25978f * h)
    cubicTo(0.40639f * w, 0.26644f * h, 0.41130f * w, 0.27197f * h, 0.41759f * w, 0.27544f * h)
    lineTo(0.45414f * w, 0.29556f * h)
    cubicTo(0.46402f * w, 0.30100f * h, 0.47606f * w, 0.30070f * h, 0.48565f * w, 0.29477f * h)
    lineTo(0.49192f * w, 0.29089f * h)
    cubicTo(0.50402f * w, 0.28341f * h, 0.51965f * w, 0.28504f * h, 0.52994f * w, 0.29487f * h)
    lineTo(0.55156f * w, 0.31553f * h)
    cubicTo(0.56069f * w, 0.32425f * h, 0.56368f * w, 0.33761f * h, 0.55913f * w, 0.34938f * h)
    lineTo(0.55311f * w, 0.36498f * h)
    cubicTo(0.55020f * w, 0.37250f * h, 0.55032f * w, 0.38084f * h, 0.55342f * w, 0.38828f * h)
    lineTo(0.57723f * w, 0.44527f * h)
    val cx = 0.21660f * w
    val cy = 0.36534f * h
    val cw = (0.48456f - 0.21660f) * w
    val ch = (0.63369f - 0.36534f) * h
    addArc(Rect(cx, cy, cx + cw, cy + ch), 90f, 270f)
}
