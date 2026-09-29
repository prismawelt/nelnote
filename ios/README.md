# NEL NOTE 아이폰 앱

iOS 16 이상용 SwiftUI 앱과 WidgetKit 홈 화면 위젯입니다. 기존 앱의 기록·배경·백업 형식을 유지합니다.

## IPA 설치와 위젯

1. 저장소의 **Releases**에서 최신 **NelNote.ipa**를 받습니다.
2. AltStore 등으로 본인 계정 서명 후 설치합니다. **NelNoteWidgets 확장을 제거하지 마세요.**
3. 앱을 한 번 열고 진행 중인 작품을 추가합니다.
4. 홈 화면을 길게 누르고 위젯 추가에서 **NEL NOTE / 도장깨기**를 선택합니다.

소형은 작품 하나, 중형은 최대 두 작품, 대형은 최대 네 작품을 보여줍니다. GAME·ANIME·V-NOVEL·BOOK 순서로 묶고, 각 분류 안에서는 최근 수정한 작품부터 표시합니다. 대형은 각 분류의 작품을 하나씩 먼저 배정합니다. 표시되지 않은 작품도 분류별 개수와 전체 개수에는 포함됩니다.

위젯에서 작품을 누르면 앱의 해당 기록이 열립니다. 진행 단위나 전체 수량이 없는 작품은 임의의 진행률을 표시하지 않습니다. 앱에서 추가·수정·완료·삭제·불러오기·되돌리기를 하면 공유 데이터를 저장하고 위젯 갱신을 요청합니다. 실제 표시 시점은 iOS가 정합니다.

### 서명과 App Groups

IPA는 Apple 배포용으로 서명되지 않았습니다. 재서명 도구가 권한을 읽을 수 있도록 임시 서명에 App Group 정보를 보존합니다. 앱과 위젯을 같은 팀으로 서명하고, 양쪽에 같은 App Group 권한이 있어야 데이터가 표시됩니다. AltStore가 그룹 이름을 바꾸면 ALTAppGroups에 기록된 그룹을 사용합니다. 위젯이 “앱을 한 번 열어 주세요”에 머무르면 설치한 앱의 확장 및 App Group 권한을 확인하세요.

Xcode로 직접 빌드할 때는 project.yml의 APP_GROUP_IDENTIFIER를 본인 개발자 계정에 등록된 그룹으로 바꾸고 앱·위젯 모두에 같은 팀을 지정하세요. 기본 그룹은 group.com.nelnote.app입니다.

## 빌드와 검증

main에 iOS 코드를 푸시하거나 **Actions → Build iOS IPA → Run workflow**를 실행합니다. 워크플로는 다음을 수행합니다.

- XcodeGen으로 앱·위젯·테스트 타깃 생성
- iPhone 시뮬레이터에서 데이터 동기화, 작품 링크, 연속 탭·스와이프 테스트
- 위젯 크기별 검토 이미지와 테스트 결과 보관
- 실제 iPhone용 앱·위젯을 빌드하고, 확장·권한·URL 연결이 포함된 IPA 검증
- 성공한 main 빌드를 Releases에 게시

Mac에서 직접 검증하려면:

    cd ios
    xcodegen generate
    xcodebuild -project NelNote.xcodeproj -scheme NelNote \
      -destination 'platform=iOS Simulator,name=iPhone 17' test

사용 가능한 시뮬레이터 이름에 맞춰 destination을 바꾸세요. GitHub Actions의 검증은 시뮬레이터와 패키지 수준이며, 설치 계정의 서명과 실제 기기의 위젯 동작은 기기에서 확인해야 합니다.

## 기록 보존

기록은 기존 Application Support/NelNoteNative/items.json에 계속 저장합니다. 위젯에는 읽기 전용 요약만 별도로 전달합니다. 기존 웹뷰 IPA의 기록과 배경 이전도 유지합니다. 앱 삭제 전에는 설정에서 백업하세요.

ios/Sources와 ios/Resources는 이전 웹뷰 버전으로, 현재 빌드에는 포함하지 않습니다.
