import * as pdfjsLib from "pdfjs-dist";

// pdf.js ships its renderer as a separate worker; point GlobalWorkerOptions at
// the bundled worker so getDocument() can render on a background thread. CRA
// copies `public/` to the build root verbatim.
pdfjsLib.GlobalWorkerOptions.workerSrc = `${process.env.PUBLIC_URL || ""}/pdfjs/pdf.worker.min.mjs`;

export async function loadPdf(url) {
  return pdfjsLib.getDocument({ url }).promise;
}

export default pdfjsLib;
