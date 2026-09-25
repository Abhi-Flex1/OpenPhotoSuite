@Entry
@Component
struct Index {
  build() {
    Column() {
      Text('PhotoSuite tests')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#171A1C')
  }
}
