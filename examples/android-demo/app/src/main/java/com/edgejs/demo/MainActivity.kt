package com.edgejs.demo

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp

/**
 * Main activity for the Edge.js Android demo.
 *
 * Copies `hello.js` from assets to internal storage on first launch, then
 * provides Start/Stop buttons to control the Edge.js runtime.
 */
class MainActivity : ComponentActivity() {

    private lateinit var manager: EdgeJSManager

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        manager = EdgeJSManager()

        // Copy the JS entry script from assets to internal storage so that
        // the native runtime can access it via a filesystem path.
        val scriptPath = copyAssetToInternal("js/hello.js")

        setContent {
            MaterialTheme {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background
                ) {
                    EdgeJSDemoScreen(manager = manager, scriptPath = scriptPath)
                }
            }
        }
    }

    /**
     * Copy an asset file to the app's internal files directory and return
     * the absolute path.
     */
    private fun copyAssetToInternal(assetName: String): String {
        val outFile = java.io.File(filesDir, assetName)
        outFile.parentFile?.mkdirs()

        if (!outFile.exists()) {
            assets.open(assetName).use { input ->
                outFile.outputStream().use { output ->
                    input.copyTo(output)
                }
            }
        }

        return outFile.absolutePath
    }
}

@Composable
fun EdgeJSDemoScreen(manager: EdgeJSManager, scriptPath: String) {
    val isRunning by manager.isRunning.collectAsState()
    val lastOutput by manager.lastOutput.collectAsState()

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Text(
            text = "Edge.js Android Demo",
            style = MaterialTheme.typography.headlineMedium
        )

        // Status indicator
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Box(
                modifier = Modifier
                    .size(12.dp)
                    .clip(CircleShape)
                    .background(if (isRunning) Color.Green else Color.Gray)
            )
            Text(
                text = if (isRunning) "Running" else "Stopped",
                color = if (isRunning) Color(0xFF2E7D32) else Color.Gray
            )
        }

        // Start / Stop buttons
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Button(
                onClick = { manager.start(scriptPath) },
                enabled = !isRunning
            ) {
                Text("Start")
            }

            OutlinedButton(
                onClick = { manager.stop() },
                enabled = isRunning
            ) {
                Text("Stop")
            }
        }

        // Output area
        OutlinedCard(
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f)
        ) {
            Column(modifier = Modifier.padding(12.dp)) {
                Text(
                    text = "Output",
                    style = MaterialTheme.typography.titleSmall
                )
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    text = lastOutput,
                    fontFamily = FontFamily.Monospace,
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier
                        .fillMaxWidth()
                        .verticalScroll(rememberScrollState())
                )
            }
        }
    }
}
