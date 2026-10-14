import Foundation
import MediaForgeCore

func userError(_ error: Error) -> String {
    #if canImport(ImageIO)
    if let imageError = error as? ImageConversionError {
        switch imageError {
        case .invalidRequest: return L("Неверные параметры изображения. Проверьте размеры и качество.")
        case .invalidSource: return L("Не удалось прочитать изображение.")
        case .unsupportedFormat: return L("Формат изображения не поддерживается системой.")
        case .animationConsentRequired: return L("Нужно подтвердить потерю анимации.")
        case .flattenColorRequired: return L("Выберите фон для замены прозрачности.")
        case .destinationExists: return L("Файл результата уже существует.")
        case .encodingFailed, .verificationFailed: return L("Не удалось создать или проверить изображение. Подробности в журнале.")
        case .fileOperation: return L("Не удалось записать изображение. Проверьте папку результатов.")
        }
    }
    #endif
    guard let error = error as? MediaForgeError else { return error.localizedDescription }
    switch error {
    case .missingTool: return L("Встроенный движок не найден. Переустановите приложение; дополнительная установка FFmpeg не требуется.")
    case .outputExists(let url): return L("Файл результата уже существует:") + " " + url.lastPathComponent
    case .processFailed(let code, _): return L("Движок завершился с ошибкой. Подробности доступны в журнале. Код:") + " " + String(code)
    case .invalidMedia: return L("Файл пуст, повреждён или не содержит поддерживаемых медиапотоков.")
    case .unsupported: return L("Этот формат или кодек недоступен для выбранного файла. Проверьте информацию о файле и движке.")
    case .fileOperation: return L("Не удалось записать результат. Проверьте доступ к папке и свободное место.")
    case .invalidSettings(let message):
        if message.contains("sample rate") { return L("Неподдерживаемая частота дискретизации. Используйте, например, 44100 или 48000 Гц.") }
        if message.contains("mono or stereo") { return L("Число каналов должно быть 1 или 2.") }
        if message.contains("Target size") { return L("Целевой размер должен быть больше нуля и не больше 100000 МБ.") }
        if message.contains("Dimensions must be numbers") { return L("Размеры должны быть целыми числами от 1 до 16384.") }
        if message.contains("Dimensions") { return L("Размеры должны быть чётными числами от 2 до 16384.") }
        if message.contains("Video bitrate") { return L("Битрейт видео: от 16 до 200000 кбит/с.") }
        if message.contains("Audio bitrate") { return L("Битрейт аудио: от 8 до 1536 кбит/с.") }
        if message.contains("Frame rate") { return L("Частота кадров: от 1 до 240.") }
        if message.contains("duration") { return L("Границы обрезки выходят за длительность файла.") }
        return L("Проверьте параметры обрезки: начало неотрицательно, конец позже начала.")
    }
}
