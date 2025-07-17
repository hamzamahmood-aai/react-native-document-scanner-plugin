import UIKit
import VisionKit

@available(iOS 13.0, *)
class DocScanner: NSObject {
    
    private var successHandler: (([String]) -> Void)?
    private var errorHandler: ((String) -> Void)?
    private var cancelHandler: (() -> Void)?
    private var maxNumDocuments: Int = 1
    
    func startScan(
        _ presentingViewController: UIViewController,
        successHandler: @escaping ([String]) -> Void,
        errorHandler: @escaping (String) -> Void,
        cancelHandler: @escaping () -> Void,
        responseType: String? = nil,
        croppedImageQuality: Int? = nil,
        maxNumDocuments: Int = 1
    ) {
        self.successHandler = successHandler
        self.errorHandler = errorHandler
        self.cancelHandler = cancelHandler
        self.maxNumDocuments = maxNumDocuments
        
        guard VNDocumentCameraViewController.isSupported else {
            errorHandler("Document camera is not supported on this device")
            return
        }
        
        let scannerViewController = VNDocumentCameraViewController()
        scannerViewController.delegate = self
        presentingViewController.present(scannerViewController, animated: true)
    }
}

@available(iOS 13.0, *)
extension DocScanner: VNDocumentCameraViewControllerDelegate {
    
    func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
        controller.dismiss(animated: true)
        
        var scannedImages: [String] = []
        
        // Respect maxNumDocuments limit
        let documentsToProcess = min(scan.pageCount, maxNumDocuments)
        
        for i in 0..<documentsToProcess {
            let image = scan.imageOfPage(at: i)
            
            // Convert to JPEG with quality
            let quality: CGFloat = 0.8 // Default quality
            guard let imageData = image.jpegData(compressionQuality: quality) else {
                continue
            }
            
            // Save to temporary directory
            let tempDirectory = FileManager.default.temporaryDirectory
            let filename = "scanned_document_\(Date().timeIntervalSince1970)_\(i).jpg"
            let fileURL = tempDirectory.appendingPathComponent(filename)
            
            do {
                try imageData.write(to: fileURL)
                scannedImages.append(fileURL.path)
            } catch {
                print("Failed to save scanned image: \(error.localizedDescription)")
            }
        }
        
        successHandler?(scannedImages)
        cleanup()
    }
    
    func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
        controller.dismiss(animated: true)
        errorHandler?(error.localizedDescription)
        cleanup()
    }
    
    func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
        controller.dismiss(animated: true)
        cancelHandler?()
        cleanup()
    }
    
    private func cleanup() {
        successHandler = nil
        errorHandler = nil
        cancelHandler = nil
    }
}

@available(iOS 13.0, *)
@objc(DocumentScanner)
class DocumentScanner: NSObject {

    @objc static func requiresMainQueueSetup() -> Bool {
        return true
    }
    
    /** @property  documentScanner the document scanner */
    private var documentScanner: DocScanner?

    @objc(scanDocument:withResolver:withRejecter:)
    func scanDocument(
      _ options: NSDictionary,
      resolve: @escaping RCTPromiseResolveBlock,
      reject: @escaping RCTPromiseRejectBlock
    ) -> Void {
        DispatchQueue.main.async {
            self.documentScanner = DocScanner()

            // Extract maxNumDocuments from options, default to 1 for iOS
            let maxNumDocuments = options["maxNumDocuments"] as? Int ?? 1
            
            // Get the quality setting
            let quality = options["croppedImageQuality"] as? Int ?? 80

            // launch the document scanner
            self.documentScanner?.startScan(
                RCTPresentedViewController(),
                successHandler: { (scannedDocumentImages: [String]) in
                    // document scan success - images are already limited by maxNumDocuments
                    resolve([
                        "status": "success",
                        "scannedImages": scannedDocumentImages
                    ])
                    self.documentScanner = nil
                },
                errorHandler: { (errorMessage: String) in
                    // document scan error
                    reject("document scan error", errorMessage, nil)
                    self.documentScanner = nil
                },
                cancelHandler: {
                    // when user cancels document scan
                    resolve([
                        "status": "cancel"
                    ])
                    self.documentScanner = nil
                },
                responseType: options["responseType"] as? String,
                croppedImageQuality: quality,
                maxNumDocuments: maxNumDocuments
            )
        }
    }
}

// Helper function to get the presented view controller
func RCTPresentedViewController() -> UIViewController {
    guard let keyWindow = UIApplication.shared.windows.first(where: { $0.isKeyWindow }),
          let rootViewController = keyWindow.rootViewController else {
        return UIViewController()
    }
    
    return topViewController(rootViewController)
}

func topViewController(_ rootViewController: UIViewController) -> UIViewController {
    if let presentedViewController = rootViewController.presentedViewController {
        return topViewController(presentedViewController)
    }
    
    if let navigationController = rootViewController as? UINavigationController {
        return topViewController(navigationController.visibleViewController!)
    }
    
    if let tabController = rootViewController as? UITabBarController {
        return topViewController(tabController.selectedViewController!)
    }
    
    return rootViewController
}
