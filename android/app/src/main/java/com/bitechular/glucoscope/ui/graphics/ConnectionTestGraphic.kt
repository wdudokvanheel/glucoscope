package com.bitechular.glucoscope.ui.graphics

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.aspectRatio
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
import com.bitechular.glucoscope.ui.screens.onboarding.ConnectionTestState
import kotlin.math.max

@Composable
fun ThemedConnectionTestGraphic(state: ConnectionTestState?, modifier: Modifier = Modifier) {
    val prefs = PreferenceModel.current

    SquareContainer(modifier) {
        ConnectionTestGraphic(
            state = state,
            background = prefs.theme.background,
            iconFill = prefs.theme.text,
            pendingColor = prefs.theme.highColor,
            successColor = prefs.theme.inRangeColor,
            failColor = prefs.theme.lowColor
        )
    }
}

@Composable
fun ConnectionTestGraphic(
    state: ConnectionTestState?,
    background: Color = Color.Black,
    iconFill: Color = Color.White,
    pendingColor: Color = Color(0xFFFFA500),
    successColor: Color = Color.Green,
    failColor: Color = Color.Red,
    modifier: Modifier = Modifier
) {
    val powerLightColor = when (state) {
        is ConnectionTestState.Success -> successColor
        is ConnectionTestState.Pending -> pendingColor
        else -> failColor
    }

    BoxWithConstraints(
        modifier = modifier
            .background(background)
            .aspectRatio(1f)
    ) {
        Canvas(Modifier.fillMaxSize()) {
            /* Cloud and its overlay gradient */
            drawPath(ConnectionSettingsCloudShape.path(size), iconFill)
            drawPath(
                ConnectionSettingsCloudShape.path(size),
                Brush.linearGradient(
                    listOf(
                        Color.Black.copy(alpha = 0f),
                        Color.Black.copy(alpha = 0.15f)
                    ),
                    start = Offset(
                        size.width * 0.5f,
                        size.height * (ConnectionSettingsCloudShape.TOP + 0.1f)
                    ),
                    end = Offset(
                        size.width * 0.5f,
                        size.height * ConnectionSettingsCloudShape.BOTTOM
                    )
                )
            )

            /* App rectangle + glossy overlay */
            val appRect = Rect(
                Offset(size.width * 0.25f, size.height * 0.75f),
                Size(size.width * 0.5f, size.height * 0.5f)
            )
            drawRoundRect(iconFill, appRect.topLeft, appRect.size, CornerRadius(16f))
            drawRoundRect(
                Brush.linearGradient(
                    colors = listOf(
                        Color.Black.copy(alpha = 0f),
                        Color.Black.copy(alpha = 0f),
                        Color.Black.copy(alpha = 0.15f)
                    ),
                    start = Offset(size.width * 0.5f, size.height * 0.65f),
                    end = Offset(size.width * 0.5f, size.height)
                ),
                appRect.topLeft,
                appRect.size,
                CornerRadius(16f)
            )

            /* Burger menu, power-light, and state indicator */
            ConnectionSettingsBurgerMenu.draw(this, background, iconFill)
            ConnectionSettingsPowerLightIcon.draw(this, powerLightColor)

            when (state) {
                is ConnectionTestState.Success -> drawPath(
                    ConnectionSettingsCheckShape.path(size),
                    successColor,
                    style = Stroke(
                        width = size.minDimension * 0.03f,
                        cap = StrokeCap.Round,
                        join = StrokeJoin.Round
                    )
                )

                is ConnectionTestState.Failed -> drawPath(
                    ConnectionSettingsCrossShape.path(size),
                    failColor,
                    style = Stroke(
                        width = size.minDimension * 0.03f,
                        cap = StrokeCap.Round,
                        join = StrokeJoin.Round
                    )
                )

                else -> ConnectionSettingsDrop.draw(this, failColor)
            }
        }
    }
}

/* ---------- 3) Shapes & helpers ---------- */

object ConnectionSettingsCloudShape {
    const val LEFT = 0.26573f
    const val RIGHT = 0.73437f
    const val TOP = 0.06477f
    const val BOTTOM = 0.36327f

    fun path(size: Size) = Path().apply {
        val w = size.width
        val h = size.height
        moveTo(0.65076f * w, BOTTOM * h)
        lineTo(0.35796f * w, BOTTOM * h)
        cubicTo(0.33474f * w, 0.36357f * h, 0.31228f * w, 0.35524f * h, 0.29514f * w, 0.33996f * h)
        cubicTo(0.27801f * w, 0.32469f * h, 0.26749f * w, 0.30363f * h, LEFT * w, 0.28107f * h)
        cubicTo(LEFT * w, 0.27869f * h, LEFT * w, 0.27632f * h, LEFT * w, 0.27394f * h)
        cubicTo(0.26478f * w, 0.25527f * h, 0.27032f * w, 0.23682f * h, 0.28143f * w, 0.22158f * h)
        cubicTo(0.29255f * w, 0.20633f * h, 0.30861f * w, 0.19518f * h, 0.32703f * w, 0.18991f * h)
        cubicTo(0.32703f * w, 0.18736f * h, 0.32703f * w, 0.1848f * h, 0.32703f * w, 0.18242f * h)
        cubicTo(0.3277f * w, 0.15937f * h, 0.33488f * w, 0.13695f * h, 0.34778f * w, 0.11761f * h)
        cubicTo(0.36068f * w, 0.09828f * h, 0.37879f * w, 0.08278f * h, 0.40013f * w, 0.07282f * h)
        cubicTo(0.42323f * w, 0.0628f * h, 0.44894f * w, 0.05999f * h, 0.47374f * w, TOP * h)
        cubicTo(0.49853f * w, 0.06954f * h, 0.52121f * w, 0.08167f * h, 0.53866f * w, 0.09949f * h)
        cubicTo(0.55059f * w, 0.11133f * h, 0.56018f * w, 0.1252f * h, 0.56697f * w, 0.14041f * h)
        cubicTo(0.57378f * w, 0.13491f * h, 0.58186f * w, 0.1311f * h, 0.59051f * w, 0.12932f * h)
        cubicTo(0.59917f * w, 0.12754f * h, 0.60814f * w, 0.12783f * h, 0.61665f * w, 0.13018f * h)
        cubicTo(0.62914f * w, 0.13446f * h, 0.64003f * w, 0.14231f * h, 0.64788f * w, 0.1527f * h)
        cubicTo(0.65574f * w, 0.16309f * h, 0.66021f * w, 0.17555f * h, 0.6607f * w, 0.18845f * h)
        cubicTo(0.6815f * w, 0.19193f * h, 0.70034f * w, 0.20252f * h, 0.71385f * w, 0.21833f * h)
        cubicTo(0.72735f * w, 0.23413f * h, RIGHT * w, 0.25411f * h, RIGHT * w, 0.27468f * h)
        cubicTo(RIGHT * w, 0.3556f * h, 0.6517f * w, 0.36309f * h, 0.65076f * w, BOTTOM * h)
        close()
    }
}

object ConnectionSettingsDropShape {
    const val LEFT = 0.43066f
    const val RIGHT = 0.55566f
    const val TOP = 0.46976f
    const val BOTTOM = 0.63867f

    fun path(size: Size) = Path().apply {
        val w = size.width
        val h = size.height
        val leftX = LEFT * w
        val rightX = RIGHT * w
        val topY = TOP * h
        val bottomY = BOTTOM * h
        moveTo(leftX, 0.57584f * h)
        cubicTo(leftX, 0.54778f * h, 0.47151f * w, 0.49063f * h, 0.48716f * w, topY)
        cubicTo(0.49019f * w, 0.46572f * h, 0.49613f * w, 0.46572f * h, 0.49917f * w, topY)
        cubicTo(0.51481f * w, 0.49063f * h, rightX, 0.54778f * h, rightX, 0.57584f * h)
        cubicTo(rightX, 0.61054f * h, 0.52768f * w, bottomY, 0.49316f * w, bottomY)
        cubicTo(0.45865f * w, bottomY, leftX, 0.61054f * h, leftX, 0.57584f * h)
    }
}

object ConnectionSettingsCheckShape {
    fun path(size: Size) = Path().apply {
        val w = size.width;
        val h = size.height
        moveTo(0.37305f * w, 0.54568f * h)
        lineTo(0.46342f * w, 0.63822f * h)
        lineTo(0.62695f * w, 0.47363f * h)
    }
}

object ConnectionSettingsCrossShape {
    fun path(size: Size) = Path().apply {
        val w = size.width;
        val h = size.height
        moveTo(0.57991f * w, 0.63965f * h)
        lineTo(0.41978f * w, 0.47363f * h)
        moveTo(0.58301f * w, 0.47363f * h)
        lineTo(0.41699f * w, 0.63965f * h)
    }
}

/* ---------- 4) Helpers converted to `(scope, …)` style ---------- */

object ConnectionSettingsBurgerMenu {
    fun draw(scope: DrawScope, background: Color, foreground: Color) = with(scope) {
        val w = size.width
        val h = size.height
        val barW = 0.0625f * w
        val barH = 0.01563f * h
        val xOff = 0.64258f * w
        listOf(0.80273f, 0.82959f).forEach { yFactor ->
            val y = yFactor * h
            drawRoundRect(
                color = background,
                topLeft = Offset(xOff, y),
                size = Size(barW, barH),
                cornerRadius = CornerRadius(32f)
            )
            // simple inner shadow outline
            drawRoundRect(
                color = foreground,
                topLeft = Offset(xOff, y),
                size = Size(barW, barH),
                cornerRadius = CornerRadius(32f),
                style = Stroke(width = 1f)
            )
        }
    }
}

object ConnectionSettingsPowerLightIcon {
    fun draw(scope: DrawScope, color: Color) = with(scope) {
        val w = size.width
        val h = size.height
        val lightW = 0.0625f * w
        val lightH = 0.03125f * h
        val lightX = 0.29492f * w
        val lightY = 0.80273f * h

        drawRoundRect(
            color = color,
            topLeft = Offset(lightX, lightY),
            size = Size(lightW, lightH),
            cornerRadius = CornerRadius(lightH / 2)
        )
        drawRoundRect(
            Brush.radialGradient(
                listOf(
                    Color.White.copy(alpha = 0.15f),
                    Color.Transparent
                ),
                center = Offset(lightX + lightW / 2f, lightY + lightH / 2f),
                radius = max(lightW, lightH) / 2f
            ),
            Offset(lightX, lightY),
            Size(lightW, lightH),
            CornerRadius(lightH / 2)
        )
    }
}

object ConnectionSettingsDrop {
    fun draw(scope: DrawScope, fill: Color) = with(scope) {
        drawPath(ConnectionSettingsDropShape.path(size), fill)
        drawPath(
            ConnectionSettingsDropShape.path(size),
            Brush.linearGradient(
                listOf(
                    Color.Black.copy(alpha = 0f),
                    Color.Black.copy(alpha = 0.5f)
                ),
                start = Offset(size.width * 0.5f, size.height * ConnectionSettingsDropShape.TOP),
                end = Offset(size.width * 0.5f, size.height * ConnectionSettingsDropShape.BOTTOM)
            )
        )
    }
}