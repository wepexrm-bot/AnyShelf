import * as pdfjsLib from "pdfjs-dist";

// pdf.js ships its renderer as a separate worker; point GlobalWorkerOptions at
// the bundled worker so getDocument() can render on a background thread. CRA
// copies `public/` to the build root verbatim.
pdfjsLib.GlobalWorkerOptions.workerSrc = `${process.env.PUBLIC_URL || ""}/pdfjs/pdf.worker.min.mjs`;

export async function loadPdf(url) {
  return pdfjsLib.getDocument({ url }).promise;
}

// Does this PDF page draw any embedded raster images (covers, plates, photos)?
// Used by the reader's text mode: pages with images keep showing the themed PDF
// canvas, so covers/illustrations aren't hidden when fonts are substituted.
// The operator list is generated once per page by pdf.js and cached internally,
// so repeated checks are cheap.
const IMAGE_OPS = new Set([
  pdfjsLib.OPS.paintImageMaskXObject, // 83
  pdfjsLib.OPS.paintImageMaskXObjectGroup, // 84
  pdfjsLib.OPS.paintImageXObject, // 85
  pdfjsLib.OPS.paintInlineImageXObject, // 86
  pdfjsLib.OPS.paintInlineImageXObjectGroup, // 87
  pdfjsLib.OPS.paintImageXObjectRepeat, // 88
]);

export async function pageHasImages(pdfPage) {
  try {
    const { fnArray } = await pdfPage.getOperatorList();
    return fnArray.some((fn) => IMAGE_OPS.has(fn));
  } catch {
    return false;
  }
}

export default pdfjsLib;
