import CoreML
import CryptoKit

/// Downloads and compiles a CoreML model from somewhere on the interwebs.
@available(iOS 15.0.0, *)
@available(macOS 12.0, *)
public struct CoreMLDownloader {
    var latestEndpoint: URL
    var downloadEndpoint: URL
    var token: String
    let fileManager = FileManager.default
    let modelUrl = FileManager.default.urls(
        for: .documentDirectory,
        in: .userDomainMask
    )[0].appendingPathComponent("model.mlmodel")
    
    /// Init with separate latest version and download endpoints
    public init(
        latestEndpoint: URL,
        downloadEndpoint: URL,
        token: String
    ) {
        self.latestEndpoint = latestEndpoint
        self.downloadEndpoint = downloadEndpoint
        self.token = token
    }
    
    /// Init with combined latest version and download endpoints.
    /// Latest version is at `<endpoint>/latest` and download is at `<endpoint>/download`)
    public init(
        endpoint: URL,
        token: String
    ) {
        self.latestEndpoint = endpoint.appendingPathComponent("latest")
        self.downloadEndpoint = endpoint.appendingPathComponent("download")
        self.token = token
    }
    
    /// Downloads and compiles the CoreML model from the internet.
    public func DownloadAndCompileModel() async throws -> MLModel {
        do {
            if fileManager.fileExists(atPath: modelUrl.path) {
                var origFileMD5 = CryptoKit.Insecure.MD5()
                
                origFileMD5.update(data: try Data(contentsOf: modelUrl))
                
                print("updating model...")
                
                // If the latest model and the current model's hash values are no the same, replace the current model with the latest model
                if try await fetchLatestMD5() != origFileMD5.finalize().description.dropFirst(12) {
                    try await self.downloadAndCompile()
                } else {
                    print("model already at the latest version!")
                }
            
            // If there is no model, download the latest model version anyways
            } else {
                print("retrieving model...")
                try await self.downloadAndCompile()
            }

            let compiledUrl = try MLModel.compileModel(at: modelUrl) // Compiles the model file (goes from .mlmodel to .mlmodelc)
            return try MLModel(contentsOf: compiledUrl) // Return the new model made from the compiled model file
        } catch {
            throw error
        }
    }
    
    /// Fetches and returns the latest model's MD5 hash
    func fetchLatestMD5() async throws -> String {
        do {
            var request = URLRequest(url: latestEndpoint)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            // Get latest model's hash
            let (data, _) = try await URLSession.shared.data(for: request)
            let decoder = JSONDecoder()
            let decodedData = try decoder.decode(ModelDigest.self, from: data)
            
            return decodedData.md5
        } catch {
            print("an error occured while fetching latest model md5 hash: \(error)")
            throw error
        }
    }
    
    /// Downloads the model from the endpoint and returns a `URL` to where it is currently stored.
    func downloadAndCompile() async throws {
        
        print("downloading latest model...")
        do {
            var request = URLRequest(url: downloadEndpoint)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            let (tempUrl, _) = try await URLSession.shared.download(for: request) // Download the model from wherever it is stored
            print("done!")
            
            print("compiling model...")
            
            let modelData = try Data(contentsOf: tempUrl) // Get the raw data
            
            try modelData.write(to: modelUrl) // Write new model file
            
            print("done!")
        } catch {
            print("an error occured while downloading: \(error)")
            throw error
        }
    }
}

/// The structure of the latest version api endpoint.
/// Is fetched as a `GET` request when downloading
public struct ModelDigest: Decodable {
    public let md5: String
    public let status: String
}