//
//  AsyncWebImage.swift
//  ImageLoaderCombine
//
//  Created by Administrator on 10/07/23.
//
import UIKit
import Combine
import SwiftUI

fileprivate var downloadCache:DownloadCache = DownloadCache(downloadQueue: Downlaoder(webapi: WebAPI()), folderCache: FolderCache())

func clearSWebImageSwiftUICache(){
    downloadCache.forceStopAndClear()
}


final fileprivate class FileWriteSubscriber: Subscriber {
    
    typealias Input = (Data,URL)
    typealias Failure = Error

    func receive(subscription: Subscription) {
      subscription.request(.unlimited)
    }
    
    func receive(_ input: (Data,URL)) -> Subscribers.Demand {
            try? input.0.write(to: input.1)
      return .unlimited
    }
    
    func receive(completion: Subscribers.Completion<Error>) {
      print("Received completion", completion)
    }
  }



fileprivate protocol Cachable{
    var cacheStoreLocation:URL {get}
    func imageNameFrom(url:URL)->String
    
    func storeIn(image:UIImage, for name:String) throws
    func imageFrom(name:String) throws -> UIImage?
    
    func removeFor(name:String) throws
    func clearCacheOnly()
    func cancellAll()
}

fileprivate class FolderCache:Cachable{
    private let inputStream = PassthroughSubject<(Data,URL),Error>()
    
    init(){
        self.inputStream.subscribe(FileWriteSubscriber())
    }
    
    var cacheStoreLocation: URL{
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("Downloads")
    }
    
    func imageNameFrom(url: URL) -> String {
        //let str = (url.host ?? "nohost").appending("_".appending(url.lastPathComponent))
        //return str
        //return url.absoluteString
        let str = url.relativePath.replacingOccurrences(of: "/", with: "_")
        return str
    }
    
    func storeIn(image: UIImage, for name: String)  throws {
              if let data = image.jpegData(compressionQuality: 0.8){
            do {
                if !FileManager.default.fileExists(atPath: cacheStoreLocation.path) {
                    try FileManager.default.createDirectory(atPath: cacheStoreLocation.path, withIntermediateDirectories: true, attributes: nil)
                }
                let url = self.cacheStoreLocation.appending(path: name)
                inputStream.send((data, url))
            } catch let error as NSError {
                print("Error creating directory: \(error.localizedDescription)")
            }
        }

    }
    
    func imageFrom(name: String)  -> UIImage? {
        let url = self.cacheStoreLocation.appending(path: name)
        if let imageData = try? Data(contentsOf: url){
            return UIImage(data: imageData) //.imageResized(to: CGSize(width: 150, height: 200)
        }else{
            return nil
        }
    }
    
    func removeFor(name: String)  throws {
        let url = self.cacheStoreLocation.appending(path: name)
        try FileManager.default.removeItem(at: url)
    }
    
    func clearCacheOnly() {
        let url = self.cacheStoreLocation
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            print(error.localizedDescription)
        }
    }
    func cancellAll(){
        inputStream.send(completion: .finished)
        clearCacheOnly()
    }
    deinit{
        
    }
}

fileprivate protocol WebInteractable{
    func fetch(url:URL)-> AnyPublisher<UIImage?, Error>
}
fileprivate struct WebAPI:WebInteractable {
    func fetch(url:URL)-> AnyPublisher<UIImage?, Error> {
        Future{ promis in
            let session = URLSession.shared
            let dataTask = session.dataTask(with: URLRequest(url: url)) { data, response, error in
                if let err = error{
                    promis(.failure(err))
                }
                else{
                    if let d = data, let img = UIImage(data: d){
                        let smallImg = img.imageResized(to: CGSize(width: 150, height: 200))
                        promis(.success(smallImg))
                    }
                    promis(.success(nil))
                }
            }
            
            dataTask.resume()
        }
        .eraseToAnyPublisher()
    }
}
fileprivate protocol DownloadQueuable{
    func addDownloading(url:URL)
    func downloadCompletionStream() -> PassthroughSubject<(UIImage?, URL), Never>
    func stopAll()
}
fileprivate class Downlaoder: DownloadQueuable {
    
    private let imageDownloadedPublisher = PassthroughSubject<(UIImage?, URL), Never>()

    private let webapi:WebAPI

    private let urlStream = PassthroughSubject<URL, Never>()
    private var cancellable = Set<AnyCancellable>()
    
    init(webapi:WebAPI){
        self.webapi = webapi
        
        self.urlStream
            .distinct()
            .subscribe(on: DispatchQueue.global())
            .sink { completion in
            print("downlaodStream completion")
        } receiveValue: {[unowned self] url in

                self.webapi.fetch(url: url)
                    .sink { completion in
                        switch completion{
                        case .finished:
                            print("Finsihed called: \(url.pathComponents.reduce("",+))")
                        case .failure(_):
                            print("Failure called: \(url.pathComponents.reduce("",+))")
                        }
                    
                } receiveValue: {[unowned self] img in
                    self.imageDownloadedPublisher.send((img, url))
                }.store(in: &self.cancellable)

            }
        .store(in: &cancellable)
       
        }
    func addDownloading(url:URL){
        self.urlStream.send(url)
    }
    func downloadCompletionStream()-> PassthroughSubject<(UIImage?, URL), Never>{
        return self.imageDownloadedPublisher
    }
    func stopAll(){
        urlStream.send(completion: .finished)
        imageDownloadedPublisher.send(completion: .finished)
        cancellable.forEach { $0.cancel()}
    }
    deinit{
        cancellable.removeAll()
        urlStream.send(completion: .finished)
        imageDownloadedPublisher.send(completion: .finished)
    }
}
fileprivate protocol DownloadCachable{
    func fetchImageFor(url:URL)
    func imagePublisher() -> PassthroughSubject<(UIImage?, URL), Never>
    func clearCache()
    func forceStopAndClear()
}
class DownloadCache:DownloadCachable{
    
    private let imagePublishStream = PassthroughSubject<(UIImage?, URL), Never>()
    
    private var cancellable = Set<AnyCancellable>()
    
    private let downloader:DownloadQueuable
    private let folderCache:Cachable
    
    fileprivate init(downloadQueue:DownloadQueuable, folderCache:Cachable){
        self.downloader = downloadQueue
        self.folderCache = folderCache
        
        self.bind()
   
    }
    func bind(){
        self.downloader.downloadCompletionStream()
            .receive(on: DispatchQueue.global())
            .sink { completion in
                    print("downlaoder completion")
            } receiveValue: { (img, url) in
                
                if let timg = img
                {
                   // let smallImg = img.imageResized(to: CGSize(width: 150, height: 200))
                    try? self.folderCache.storeIn(image: timg, for: self.folderCache.imageNameFrom(url: url))
                    self.imagePublishStream.send((timg, url))
                }else{
                    self.imagePublishStream.send((nil, url))
                }
            }.store(in: &cancellable)
        
    }
    
    func fetchImageFor(url:URL){
            
        let name = self.folderCache.imageNameFrom(url: url)
        do {
        if let img =  try self.folderCache.imageFrom(name:name)
        {
           self.imagePublishStream.send((img, url))
        }
        else{
           self.downloader.addDownloading(url: url)
        }
        }catch{
        print("Error while fetching image with URL:\(url.absoluteString)")
        }
     }
    func imagePublisher() -> PassthroughSubject<(UIImage?, URL), Never> {
       return imagePublishStream
    }
    func clearCache(){
        self.folderCache.clearCacheOnly()
    }
    func forceStopAndClear(){
        imagePublishStream.send(completion: .finished)
        downloader.stopAll()
        folderCache.cancellAll()
    }
    deinit{
        self.imagePublishStream.send(completion: .finished)
        cancellable.forEach{$0.cancel()}
        self.cancellable.removeAll()
    }
}


class SWebImageSwiftUIVM:ObservableObject{
    let url:URL?
    @Published var image:UIImage?
    
    private var cancellable:Cancellable?
    init(url: URL?, image: UIImage? = nil) {
        self.url = url
        self.image = image
        
        if let turl = url{
            self.cancellable = downloadCache.imagePublisher()
                .map({ (img, url1) in
                    if turl.absoluteString == url1.absoluteString{
                        return img
                    }
                    return nil
                })
                .compactMap{$0}
                .receive(on: DispatchQueue.main)
                .sink { completion in
                    //completion
                } receiveValue: { img in
                    self.image = img
                    
                }
        }
        
    }
    func onAppear(){
        if let turl = url {
          downloadCache.fetchImageFor(url: turl)
        }
    }
}

struct SWebImageSwiftUI:View{
    
    @ObservedObject var vm:SWebImageSwiftUIVM
    
    init(vm: SWebImageSwiftUIVM) {
        self.vm = vm
    }

    var body: some View{
        ZStack{
            if let img = vm.image{
                Image(uiImage: img).resizable()
            }else{
                //Image(systemName: "hourglass").resizable().frame(width:50, height: 75)
                ProgressView().progressViewStyle(.circular).foregroundColor(.black)
            }
        }
        .onAppear{
          Task{
              vm.onAppear()
            }
        }
    }

}




extension UIImage {
    func imageResized(to size: CGSize) -> UIImage {
        return UIGraphicsImageRenderer(size: size).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}


@available(OSX 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Publisher where Self.Output : Equatable {
    public func distinct() -> AnyPublisher<Self.Output, Self.Failure> {
        self.scan(([], nil)) {
            $0.0.contains($1) ? ($0.0, nil) : ($0.0 + [$1], $1)
        }
        .compactMap { $0.1 }
        .eraseToAnyPublisher()
    }
}





















//let url = URL(string: "https://unsplash.com/photos/l3N9Q27zULw/download?ixid=M3wxMjA3fDB8MXxzZWFyY2h8M3x8cmFuZG9tfGVufDB8fHx8MTY4Nzc0ODcxM3ww&force=true")
//let filePub = FileReadPublisher(fileURL: url!)
//
//filePub.sink { compltion in
//    print("filepub sink completion",compltion)
//} receiveValue: { d in
//    print("filepub data>>>> ", d)
//}.store(in: &cancellable)


