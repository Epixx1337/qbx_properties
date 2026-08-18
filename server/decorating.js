const { PNG } = require("pngjs");
const fs = require("fs");
const webp = require("webp-converter");
const path = require("path");

const RESOURCE_NAME = GetCurrentResourceName();
const SCREENSHOTS_DIR = GetResourcePath(RESOURCE_NAME) + "/screenshots";
const IMAGE_CROP_FACTOR = 4.5;
const WEBP_QUALITY = 100;

const PNG_SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
const PNG_END = Buffer.from("IEND");

/**
 * screencapture hands back a data URI, and some builds pad the tail. Trim to the
 * exact PNG stream so the decoder does not choke on trailing bytes.
 * @param {string} data
 * @returns {Buffer}
 */
function toPngBuffer(data) {
  const base64 = typeof data === "string" ? data.replace(/^data:image\/\w+;base64,/, "") : data;
  const buffer = Buffer.isBuffer(base64) ? base64 : Buffer.from(base64, "base64");

  const start = buffer.indexOf(PNG_SIGNATURE);
  if (start < 0) throw new Error("capture did not contain a PNG stream");

  const endMarker = buffer.lastIndexOf(PNG_END);
  const end = endMarker < 0 ? buffer.length : endMarker + 8;

  return buffer.subarray(start, end);
}

/**
 * Crops a centred square out of the capture and turns green-screen pixels transparent.
 * @param {Buffer} imageBuffer - Raw PNG data
 * @param {string} outputPath - Where to write the processed PNG
 */
function processImage(imageBuffer, outputPath) {
  const source = PNG.sync.read(imageBuffer);

  const size = Math.min(source.height, source.width);
  const offsetX = Math.min(
    Math.max(Math.round(source.width / IMAGE_CROP_FACTOR), 0),
    source.width - size
  );

  const output = new PNG({ width: size, height: size });

  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const from = (source.width * y + (x + offsetX)) << 2;
      const to = (size * y + x) << 2;

      const r = source.data[from];
      const g = source.data[from + 1];
      const b = source.data[from + 2];

      if (g > r + b) {
        output.data[to] = 255;
        output.data[to + 1] = 255;
        output.data[to + 2] = 255;
        output.data[to + 3] = 0;
      } else {
        output.data[to] = r;
        output.data[to + 1] = g;
        output.data[to + 2] = b;
        output.data[to + 3] = source.data[from + 3];
      }
    }
  }

  fs.writeFileSync(outputPath, PNG.sync.write(output));
}

/**
 * Converts a single PNG to WebP and removes the original.
 * @param {string} pngPath
 */
async function convertToWebP(pngPath) {
  const outputPath = pngPath.replace(/\.png$/, ".webp");

  try {
    await webp.cwebp(pngPath, outputPath, `-q ${WEBP_QUALITY}`);
    await fs.promises.unlink(pngPath);
  } catch (error) {
    console.error(`Error converting ${path.basename(pngPath)} to WebP:`, error);
  }
}

try {
  if (!fs.existsSync(SCREENSHOTS_DIR)) {
    fs.mkdirSync(SCREENSHOTS_DIR);
  }

  onNet("screenshotFurniture", async (filename) => {
    const src = source;

    if (typeof filename !== "string" || !/^[\w]+$/.test(filename)) {
      console.error("screenshotFurniture: refusing unsafe filename", filename);
      return;
    }

    try {
      exports.screencapture.serverCapture(
        src,
        { encoding: "png" },
        async (data) => {
          try {
            const imagePath = path.join(SCREENSHOTS_DIR, `${filename}.png`);
            processImage(toPngBuffer(data), imagePath);
            await convertToWebP(imagePath);
            console.log(`screenshotFurniture: wrote ${filename}.webp`);
          } catch (error) {
            console.error(`Error processing ${filename}:`, error);
          }
        },
        "base64"
      );
    } catch (error) {
      console.error("Error in screenshotFurniture:", error);
    }
  });
} catch (error) {
  console.error("Error initializing screenshot system:", error);
}
