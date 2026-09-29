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

## 책 진행 입력

홈과 BOOK 화면의 진행 중인 책은 완독 버튼 왼쪽에서 읽은 페이지를 직접 입력할 수 있습니다. 숫자 키패드의 **입력 완료**를 누르거나 다른 항목으로 이동하면 저장합니다. 전체 페이지까지 입력해도 진행 중 상태를 유지하며, **완독**을 눌러 완료합니다. 전체 분량을 등록했다면 완독할 때 진행량도 전체 분량으로 맞춥니다. 권 단위로 등록한 책은 같은 칸에서 읽은 권수를 입력합니다.

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

## Obsidian 보관함 연결 (2.3)

설정의 **Obsidian 연결 → 보관함 폴더 선택**에서 아이폰 Obsidian이 사용하는 보관함 전체를 선택합니다.
그 아래에 네 폴더가 모두 있어야 합니다: _db_anime, _db_game, _db_vnovel, _db_book.
iOS의 폴더 접근 북마크를 저장해 앱을 다시 열어도 연결을 유지합니다. 권한이 만료되면 **다시 선택**을 누르세요.

앱 실행·복귀, 작품 수정, 실행 중 파일 변경 시 동기화합니다. 파일 제공자가 변경 알림을 보내지 않는 경우에도
앱이 활성화된 동안 20초마다 확인합니다. 설정에서 **지금 동기화**, 마지막 완료 시각과 결과, **연결 해제**를 사용할 수 있습니다.
연결 해제는 양쪽 작품 파일을 삭제하지 않습니다. 앱이 종료된 동안에는 보관함을 직접 수정하지 않습니다.

아이폰과 노트북 사이 전송은 기존 Remotely Save가 담당합니다. 양쪽 Obsidian에서 Remotely Save를 실행해야
노트북까지 변경이 전달됩니다.

### 반영되는 내용

| NEL NOTE | Obsidian |
| --- | --- |
| 제목 | title |
| 대기중 | wishlist |
| 진행중 | 애니 watching / 게임·미연시 playing / 책 reading |
| 완료 | completed |
| 중단 | dropped |
| 다음 시즌 대기 (애니) | next_cours |
| 애니 전체 화수 | episodes |
| 책 전체 쪽수 | pages |

작품 추가·삭제도 양방향으로 반영됩니다. 제목은 title 속성을 따르며, 기존 파일명과 본문 제목은 바꾸지 않습니다.
장르·제작사·감독·저자·목록형 속성과 본문은 보존합니다. 새 DB는 보관함 템플릿과 같은 속성 구성을 사용하고
분류별 notes 폴더의 미생성 노트에 링크합니다. 날짜·저자가 아직 없으므로 새 노트 링크 이름은 제목만 사용합니다.

앱 메모와 세부 진행량은 앱에만 남습니다. 미연시 전체 루트 수와 책의 권 단위 전체 분량도 앱에만 저장합니다.
권 단위 책의 pages는 별도 값으로 유지하여 전체 권수로 덮어쓰지 않습니다.
진행량·시작일·완료일이 없는 노트는 미기록으로 표시하며 임의의 날짜나 진행률을 만들지 않습니다.
기존 Anime DB의 episodes: -1은 화수 미정으로 읽고 그대로 보존합니다.

### 최초 병합, 충돌과 삭제

처음에는 분류와 제목이 일치하는 유일한 후보만 자동 연결합니다. 동명 작품이 여러 개라면 설정에서
연결 대상을 고르거나 별도 작품으로 추가합니다. 앱의 메모와 진행량은 유지합니다.
노트에 nelnote_id를 넣어 이후 제목·파일명 변경을 추적합니다. 중복 ID, 잘못된 속성 또는 불완전한 읽기가
발견되면 그 동기화의 쓰기와 삭제를 시작하지 않습니다.

마지막 동기화 값과 비교해 서로 다른 속성 변경은 합칩니다. 같은 속성을 양쪽에서 바꾸면 앱의 해당 속성
변경 시각과 Obsidian 파일 수정 시각을 비교하고, 같으면 Obsidian 값을 적용합니다.
장치 시계와 Remotely Save가 전달한 파일 수정 시각에 따라 충돌 결과가 정해집니다.

앱에서 삭제한 연결 DB는 보관함의 .trash/nelnote 아래로 옮깁니다. notes의 별도 글은 삭제하지 않습니다.
앱의 **되돌리기**는 해당 DB와 본문을 복구합니다. 삭제 기록과 대기 중 변경은 앱에 저장하여 재실행 후에도
재시도하고, 삭제된 작품이 다시 들어오는 것을 막습니다. 첫 연결이나 백업 불러오기는 비어 있는 목록을
상대편 전체 삭제로 취급하지 않습니다.

### 동기화 검증

GitHub Actions는 앱·위젯 테스트 외에 YAML 보존, 네 분류 왕복, 충돌, 삭제·되돌리기,
파일명 변경, 중복, 읽기·쓰기 실패와 재시도, 백업 호환성, 1,000개 목록과 검색 화면을 검사합니다.
파일 작업과 YAML 해석은 별도 직렬 작업 큐에서 수행합니다.

Mac 또는 Swift가 설치된 Linux에서 파일 동기화 부분만 검증할 수도 있습니다:

    swift test --package-path ios

실제 보관함을 수정하지 않고 읽기만 검사하려면:

    NELNOTE_AUDIT_VAULT=/path/to/vault swift test --package-path ios --filter testExistingVaultReadOnlyWhenRequested

실제 기기 확인 순서:

1. AltStore에서 새 IPA를 설치할 때 위젯 확장을 유지합니다.
2. 설정에서 아이폰 보관함을 선택하고 최초 동기화를 완료합니다.
3. 테스트 작품을 추가·수정하고 아이폰 DB 및 위젯에 반영되는지 확인합니다.
4. 아이폰·노트북 Remotely Save를 실행하고, 노트북에서 title 또는 status를 수정합니다.
5. 다시 Remotely Save를 실행한 뒤 NEL NOTE로 복귀해 앱과 위젯 반영을 확인합니다.
6. 테스트 작품을 삭제하고 DB의 휴지통 이동, 되돌리기를 확인한 뒤 테스트 기록만 정리합니다.

API 참고: [Apple 폴더 접근](https://developer.apple.com/documentation/uikit/providing-access-to-directories),
[Yams](https://github.com/jpsim/Yams), [Remotely Save](https://github.com/remotely-save/remotely-save#features).
