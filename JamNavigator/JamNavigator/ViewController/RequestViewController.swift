//
//  RequestViewController.swift
//  JamNavigator
//
//  Created by Tasuku Furuki on 2021/12/16.
//

import UIKit
import MapKit
import CoreLocation
import Tono

class RequestViewController: UIViewController,CLLocationManagerDelegate,MKMapViewDelegate, UIPickerViewDelegate, UIPickerViewDataSource {
    @IBOutlet weak var mapView: MKMapView!
    var locationManager: CLLocationManager!
    @IBOutlet weak var dayPicker: UIDatePicker!
    @IBOutlet weak var fromtimePicker: UIDatePicker!
    @IBOutlet weak var totimePicker: UIDatePicker!
    @IBOutlet weak var drumrollPicker: UIPickerView!
    @IBOutlet weak var spanText: UILabel!
    
    let datalist = ["2","3", "4", "5", "6", "7", "8"]

    var userSub: String = ""    // ユーザー認証した時に収集した、ユーザーを識別するID
    var demotape: Demotape? = nil

    var selectedLocationId: String? = nil   // 地図タップで選択したロケーションの Address.idが格納される

    enum Modes {
        case NA
        case Request
        case Confirm
    }
    var mode: Modes = .NA
    
    // 初期化処理
    override func viewDidLoad() {
        super.viewDidLoad()
        
        do {
            if let demotape = demotape {
                mode = demotape.userId == "MATCHING" ? .Confirm : .Request
            }
        }
        
        locationManager = CLLocationManager()
        locationManager.delegate = self
        locationManager!.requestWhenInUseAuthorization()
        
        // マップの初期設定
        let span = MKCoordinateSpan(latitudeDelta:0.01, longitudeDelta: 0.01)
        let nagoyaStation = CLLocationCoordinate2DMake(35.170915, 136.8793482)
        let region = MKCoordinateRegion(center: nagoyaStation, span: span)
        mapView.region = region
        if mode == .Request {
            addPins()
        }
        mapView.delegate = self
        
        // 人数ピッカー設定
        drumrollPicker.delegate = self
        drumrollPicker.dataSource = self
        drumrollPicker.selectRow(0, inComponent: 0, animated: false)
        
        // マッチングアイテムモードで開いたときの初期化処理
        initViewAsMatchingCondition()
    }
    
    // マッチング確認状態の時は、matchingItem(demotape)から、値を自動入力する
    private func initViewAsMatchingCondition() {
        guard let matchingItem = demotape else {
            fatalError("demotapeが nilなのに、このView表示されるのはおかしいので停止")
        }
        if matchingItem.userId != "MATCHING" {
            return
        }
        
        // 日付の自動入力
        let dateFormatter: DateFormatter = DateFormatter()
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.dateFormat = "yyyy-MM-dd"
        guard let datestr = matchingItem.getValue(key: "DATEFT") else { fatalError("日付がnilになっている状態は想定外のため停止") }
        let meetingDate = dateFormatter.date(from: datestr)!
        dayPicker.date = meetingDate
        dayPicker.isEnabled = false
        
        // TimeBox
        let timeFormatter: DateFormatter = DateFormatter()
        timeFormatter.calendar = Calendar(identifier: .gregorian)
        timeFormatter.dateFormat = "hh:mm"
        guard let timeBoxFStr = matchingItem.getValue(key: "TIMEBOXF") else { fatalError("TimeBoxFがnilになっている状態は想定外のため停止") }
        let timeBoxF = timeFormatter.date(from: timeBoxFStr)!
        fromtimePicker.date = timeBoxF
        fromtimePicker.isEnabled = false
        guard let timeBoxTStr = matchingItem.getValue(key: "TIMEBOXT") else { fatalError("TimeBoxTがnilになっている状態は想定外のため停止") }
        let timeBoxT = timeFormatter.date(from: timeBoxTStr)!
        totimePicker.date = timeBoxT
        totimePicker.isEnabled = false
        
        // Span
        let span = Int(matchingItem.getValue(key: "TIMEBOXS") ?? "30") ?? 30
        spanText.text = "\(span) minutes"
        
        // 人数
        let nPplStr = matchingItem.getValue(key: "#PEOPLE") ?? "2"
        let drumIndex = datalist.firstIndex(of: nPplStr)!
        let dist = abs(drumIndex.distance(to: datalist.startIndex))
        drumrollPicker.selectRow(dist, inComponent: 0, animated: false)
        drumrollPicker.isUserInteractionEnabled = false
        
        // 地図のロケーションを指定する
        let locationId = matchingItem.getValue(key: "LOCID") ?? "n/a"
        addPin(id: locationId)
    }
    
    @IBAction func didTapRequestButton(_ sender: Any) {

        // 開始日を収集
        let daydateFormatter = DateFormatter()
        daydateFormatter.dateFormat = "yyyy-MM-dd"
        let selectedDate = daydateFormatter.string(from: dayPicker.date)
        print(selectedDate)

        // タイムボックス（開始）を取得
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        let timeBoxFrom = timeFormatter.string(from: fromtimePicker.date)
        let timeBoxTo = timeFormatter.string(from: totimePicker.date)
        print("TimeBox = \(timeBoxFrom) - \(timeBoxTo)")
        
        let span = 30
        
        // 人数を取得
        let nPpl = Int(datalist[drumrollPicker.selectedRow(inComponent: 0)]) ?? 0
        
        // ロケーションを収集
        guard let selectedLocationId = selectedLocationId else {
            alert(caption: "WARNING", message: "地図でロケーションを選択してからリクエストしてください", button1: "OK")
            return
        }

        // GraphQLで マッチングデータを保存する
        switch mode {
            case .Request:
                saveMatchingData(date: selectedDate, timeBoxFrom: timeBoxFrom, timeBoxTo: timeBoxTo, spanMinutes: span, noOfPeople: nPpl, locationId: selectedLocationId) {
                    success in
                    if success {
                        DispatchQueue.main.async {
                            self.performSegue(withIdentifier: "toRequestedComplitelyDialog", sender: self)
                        }
                    }
                }
            case .Confirm:
                setMatchingOkState() {
                    success in
                    if success {
                        DispatchQueue.main.async {
                            self.performSegue(withIdentifier: "toRequestedComplitelyDialog", sender: self)
                        }
                    }
                }
            default:
                fatalError("モード識別失敗した状態で保存ボタン押したのは想定外のパス")
        }
    }

    // 【２人限定】マッチング成立、レコード保存＋通知
    private func setMatchingOkState(callback:  ((Bool) -> Void)? = nil ) {

        guard let matchingItem = demotape else {
            fatalError("demotapeが nilなのに、マッチング成立できるのはおかしいので停止")
        }
        if matchingItem.userId != "MATCHING" {
            callback?(true)
            return
        }
        
        // 自分でリクエストしておいて、自分で確定できないように
        if let users = matchingItem.instruments {
            if users.count > 0 {
                if users[0] == userSub || users.count < 2 {
                    alert(caption: "INFO", message: "自分でリクエストしたマッチングは自分で確定できません", button1: "OK")
                    callback?(false)
                    return
                }
            }
        }

        // GraphQL（データベース）にDemotapeオブジェクトを利用して、マッチング情報を新規作成・登録する
        updateMatchingStatus(from: matchingItem, status: "WAITING_THE_REAL") {
            success, data in

            let fcmTokens = matchingItem.getValues(key: "FCMTOKEN")
            for fcmToken in fcmTokens {
                self.pushRemote(registrationToken: fcmToken, title: "Requestが確定しました！", message: "\("某月 某日 某:某")に現地集合してください！")
            }
            callback?(true)
        }
    }

    // はじめての、マッチングリクエスト
    private func saveMatchingData(date: String, timeBoxFrom: String, timeBoxTo: String, spanMinutes: Int, noOfPeople: Int, locationId: String, callback: ((Bool) -> Void)? = nil) {
        let formatter1 = DateFormatter()
        formatter1.dateFormat = "yyyy-MM-dd HH:mm"
        let dateTimeStr = formatter1.string(from: Date())
        
        // マッチングユーザーIDを作る
        let userIds = [userSub, demotape?.userId]   // 最初の UserIDが、マッチングオーナー（言い出しっぺ）

        // デモテープ作った人の FCMトークン
        guard let fcmtoken = demotape?.getValue(key: "FCMTOKEN") else {
            print("FCMトークンが見つからなかったため、PUSH通知ができません")
            alert(caption: "WARNING", message: "相手のスマホには通知が送れないため、マッチングはキャンセルされました", button1: "Cancel")
            callback?(false)
            return
        }
        
        // GraphQL（データベース）にDemotapeオブジェクトを利用して、マッチング情報を新規作成・登録する
        let tape = Demotape(
            name: "WAITING_FIRSTMATCHING",  // アンディさんが、PUSH通知受けて、OK・NGを返答するのを待っているステータス
            generatedDateTime: dateTimeStr,
            userId: "MATCHING",
            attributes: [
                "DATEFT__=\(date)",
                "TIMEBOXF=\(timeBoxFrom)",
                "TIMEBOXT=\(timeBoxTo)",
                "TIMEBOXS=\(spanMinutes)",
                "#PEOPLE_=\(noOfPeople)",
                "LOCID___=\(locationId)",
                "FCMTOKEN=\(fcmtoken)",         // デモテープ作った人のFCMトークン
                "FCMTOKEN=\(getFcmToken() ?? "?")",    // マッチングしたい人のFCMトークン
            ],
            s3StorageKey: UUID().uuidString, // マッチンググループのID
            instruments: userIds,
            nStar: 0    // 0 means no star yet.
        )
        createData(tape: tape)
        pushRemote(registrationToken: fcmtoken, title: "Requestがきました", message: "通知をタップして確認してください")
        callback?(true)
    }
    
    //  店の位置をポイントする関数
    func addPins() {
        for i in 0..<addresses.count {
            CLGeocoder().geocodeAddressString(addresses[i].address) {
                placemarks, error in
                if let coordinate = placemarks?.first?.location?.coordinate {
                    let pin = MKPointAnnotation()
                    pin.title = addresses[i].name
                    pin.coordinate = coordinate
                    self.mapView.addAnnotation(pin)
                    pin.subtitle = addresses[i].id
                }
            }
        }
    }
    
    func addPin(id: String) {
        for i in 0..<addresses.count {
            if addresses[i].id   == id {
                CLGeocoder().geocodeAddressString(addresses[i].address) {
                    placemarks, error in
                    if let coordinate = placemarks?.first?.location?.coordinate {
                        let pin = MKPointAnnotation()
                        pin.title = addresses[i].name
                        pin.coordinate = coordinate
                        self.mapView.addAnnotation(pin)
                        pin.subtitle = addresses[i].id
                        self.selectedLocationId = addresses[i].id
                    }
                }
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        switch status {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .restricted, .denied:
            break
        case .authorizedAlways, .authorizedWhenInUse:
            manager .startUpdatingLocation()
            break
        default:
            break
        }
    }
    
    func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
//        CLLocationCoordinate2D型で住所を取得
        let lc2d:CLLocationCoordinate2D = view.annotation?.coordinate as Any as! CLLocationCoordinate2D
//        上記変数をCLLocation型に変換
        let l:CLLocation = CLLocation(latitude: lc2d.latitude, longitude: lc2d.longitude)
//        上記変数をlocationに代入
        let location:CLLocation = l
        
//        住所取得：逆ジオコーティング
        CLGeocoder().reverseGeocodeLocation(location) { placemarks, error in
            guard let placemark = placemarks?.first, error == nil else { return }
            print(placemark.administrativeArea! + placemark.locality! + placemark.name!)
        }
        
//        名前の取得
        let title = (view.annotation?.title ?? "noname") ?? "noname"
        selectedLocationId = addresses.filter{ $0.name == title }.map{ $0.id }.first ?? "n/a"
    }
    
    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return 1
    }
    
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        return datalist.count
    }
    
    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        return datalist[row]
    }
    
}
