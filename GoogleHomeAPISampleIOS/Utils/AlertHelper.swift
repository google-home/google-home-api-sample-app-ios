// Copyright 2025 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import UIKit
import OSLog

class AlertHelper {
  static func showAlert(text: String) {
    // Dispatch to the main thread to present the alert.
    DispatchQueue.main.async {
      // Get the current active window.
      if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
         let rootViewController = windowScene.windows.first?.rootViewController {
        // Create and present the alert on the root view controller.
        let alert = UIAlertController(title: "Action Required", message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        rootViewController.present(alert, animated: true)
      } else {
        // Handle the error, for example, by logging it.
        Logger().error("No active window to present alert.")
      }
    }
  }
}
