#!/bin/sh
# Human-written translations for the portable Linux installer.
# This file is sourced by install-powervlc.sh; it performs no action by itself.

pvlc_installer_set_language()
{
    locale=${LANGUAGE:-${LC_ALL:-${LC_MESSAGES:-${LANG:-en}}}}
    locale=${locale%%:*}
    locale=${locale%%.*}
    locale=${locale%@*}
    locale=$(printf '%s' "$locale" | tr '-' '_')

    install_label="Install PowerVLC"
    update_label="Update PowerVLC"
    uninstall_label="Uninstall PowerVLC"
    cancel_label="Cancel"
    close_label="Close"
    launch_label="Launch PowerVLC"
    existing_prompt="PowerVLC is already installed for your account.

Choose the action to perform."
    new_prompt="PowerVLC will be installed for your account only, without administrator privileges.

Do you want to continue?"
    uninstall_prompt="Uninstall PowerVLC?

The application will be removed from your account. Your preferences and media library will be preserved."
    installed_result="PowerVLC %s was installed successfully."
    updated_result="PowerVLC %s was updated successfully."
    available_result="The application is now available in the menu."
    uninstalled_result="PowerVLC was uninstalled."
    preserved_result="Your preferences and media library were preserved."
    no_dialog_error="No graphical dialog is available. Use --install or --uninstall explicitly."

    case "$locale" in
        ca*)
            install_label="Instal·la PowerVLC"
            update_label="Actualitza PowerVLC"
            uninstall_label="Desinstal·la PowerVLC"
            cancel_label="Cancel·la"
            close_label="Tanca"
            launch_label="Inicia PowerVLC"
            existing_prompt="PowerVLC ja està instal·lat per al vostre compte.

Trieu l’acció que voleu dur a terme."
            new_prompt="PowerVLC s’instal·larà només per al vostre compte, sense privilegis d’administrador.

Voleu continuar?"
            uninstall_prompt="Voleu desinstal·lar PowerVLC?

L’aplicació se suprimirà del vostre compte. Es conservaran les preferències i la mediateca."
            installed_result="PowerVLC %s s’ha instal·lat correctament."
            updated_result="PowerVLC %s s’ha actualitzat correctament."
            available_result="L’aplicació ja està disponible al menú."
            uninstalled_result="PowerVLC s’ha desinstal·lat."
            preserved_result="S’han conservat les preferències i la mediateca."
            no_dialog_error="No hi ha cap diàleg gràfic disponible. Utilitzeu --install o --uninstall explícitament."
            ;;
        cs*)
            install_label="Nainstalovat PowerVLC"
            update_label="Aktualizovat PowerVLC"
            uninstall_label="Odinstalovat PowerVLC"
            cancel_label="Zrušit"
            close_label="Zavřít"
            launch_label="Spustit PowerVLC"
            existing_prompt="PowerVLC je již pro váš účet nainstalován.

Vyberte požadovanou akci."
            new_prompt="PowerVLC bude nainstalován pouze pro váš účet, bez oprávnění správce.

Chcete pokračovat?"
            uninstall_prompt="Odinstalovat PowerVLC?

Aplikace bude z vašeho účtu odstraněna. Předvolby a knihovna médií zůstanou zachovány."
            installed_result="PowerVLC %s byl úspěšně nainstalován."
            updated_result="PowerVLC %s byl úspěšně aktualizován."
            available_result="Aplikace je nyní dostupná v nabídce."
            uninstalled_result="PowerVLC byl odinstalován."
            preserved_result="Předvolby a knihovna médií zůstaly zachovány."
            no_dialog_error="Není dostupné žádné grafické dialogové okno. Použijte výslovně --install nebo --uninstall."
            ;;
        de*)
            install_label="PowerVLC installieren"
            update_label="PowerVLC aktualisieren"
            uninstall_label="PowerVLC deinstallieren"
            cancel_label="Abbrechen"
            close_label="Schließen"
            launch_label="PowerVLC starten"
            existing_prompt="PowerVLC ist bereits für Ihr Benutzerkonto installiert.

Wählen Sie die gewünschte Aktion."
            new_prompt="PowerVLC wird nur für Ihr Benutzerkonto und ohne Administratorrechte installiert.

Möchten Sie fortfahren?"
            uninstall_prompt="PowerVLC deinstallieren?

Die Anwendung wird aus Ihrem Benutzerkonto entfernt. Ihre Einstellungen und Medienbibliothek bleiben erhalten."
            installed_result="PowerVLC %s wurde erfolgreich installiert."
            updated_result="PowerVLC %s wurde erfolgreich aktualisiert."
            available_result="Die Anwendung ist jetzt im Menü verfügbar."
            uninstalled_result="PowerVLC wurde deinstalliert."
            preserved_result="Ihre Einstellungen und Medienbibliothek wurden beibehalten."
            no_dialog_error="Es ist kein grafischer Dialog verfügbar. Verwenden Sie ausdrücklich --install oder --uninstall."
            ;;
        es*)
            install_label="Instalar PowerVLC"
            update_label="Actualizar PowerVLC"
            uninstall_label="Desinstalar PowerVLC"
            cancel_label="Cancelar"
            close_label="Cerrar"
            launch_label="Iniciar PowerVLC"
            existing_prompt="PowerVLC ya está instalado para su cuenta.

Elija la acción que desea realizar."
            new_prompt="PowerVLC se instalará únicamente para su cuenta, sin privilegios de administrador.

¿Desea continuar?"
            uninstall_prompt="¿Desinstalar PowerVLC?

La aplicación se eliminará de su cuenta. Se conservarán sus preferencias y la biblioteca multimedia."
            installed_result="PowerVLC %s se instaló correctamente."
            updated_result="PowerVLC %s se actualizó correctamente."
            available_result="La aplicación ya está disponible en el menú."
            uninstalled_result="PowerVLC se desinstaló."
            preserved_result="Se conservaron sus preferencias y la biblioteca multimedia."
            no_dialog_error="No hay ningún diálogo gráfico disponible. Use --install o --uninstall explícitamente."
            ;;
        fr*)
            install_label="Installer PowerVLC"
            update_label="Mettre à jour PowerVLC"
            uninstall_label="Désinstaller PowerVLC"
            cancel_label="Annuler"
            close_label="Fermer"
            launch_label="Lancer PowerVLC"
            existing_prompt="PowerVLC est déjà installé pour votre compte.

Choisissez l’action à effectuer."
            new_prompt="PowerVLC va être installé uniquement pour votre compte, sans droits administrateur.

Souhaitez-vous continuer ?"
            uninstall_prompt="Désinstaller PowerVLC ?

L’application sera supprimée de votre compte. Vos préférences et votre médiathèque seront conservées."
            installed_result="PowerVLC %s a été installé avec succès."
            updated_result="PowerVLC %s a été mis à jour avec succès."
            available_result="L’application est maintenant disponible dans le menu."
            uninstalled_result="PowerVLC a été désinstallé."
            preserved_result="Vos préférences et votre médiathèque ont été conservées."
            no_dialog_error="Aucune boîte de dialogue graphique n’est disponible. Utilisez explicitement --install ou --uninstall."
            ;;
        it*)
            install_label="Installa PowerVLC"
            update_label="Aggiorna PowerVLC"
            uninstall_label="Disinstalla PowerVLC"
            cancel_label="Annulla"
            close_label="Chiudi"
            launch_label="Avvia PowerVLC"
            existing_prompt="PowerVLC è già installato per questo account.

Scegliere l’operazione da eseguire."
            new_prompt="PowerVLC verrà installato solo per questo account, senza privilegi di amministratore.

Continuare?"
            uninstall_prompt="Disinstallare PowerVLC?

L’applicazione verrà rimossa dall’account. Le preferenze e la raccolta multimediale verranno conservate."
            installed_result="PowerVLC %s è stato installato correttamente."
            updated_result="PowerVLC %s è stato aggiornato correttamente."
            available_result="L’applicazione è ora disponibile nel menu."
            uninstalled_result="PowerVLC è stato disinstallato."
            preserved_result="Le preferenze e la raccolta multimediale sono state conservate."
            no_dialog_error="Non è disponibile alcuna finestra di dialogo grafica. Usare esplicitamente --install o --uninstall."
            ;;
        ja*)
            install_label="PowerVLC をインストール"
            update_label="PowerVLC を更新"
            uninstall_label="PowerVLC をアンインストール"
            cancel_label="キャンセル"
            close_label="閉じる"
            launch_label="PowerVLC を起動"
            existing_prompt="PowerVLC はこのアカウントにすでにインストールされています。

実行する操作を選択してください。"
            new_prompt="PowerVLC は管理者権限を使わず、このアカウントのみにインストールされます。

続行しますか？"
            uninstall_prompt="PowerVLC をアンインストールしますか？

アプリケーションはこのアカウントから削除されます。設定とメディアライブラリは保持されます。"
            installed_result="PowerVLC %s を正常にインストールしました。"
            updated_result="PowerVLC %s を正常に更新しました。"
            available_result="アプリケーションがメニューから利用できるようになりました。"
            uninstalled_result="PowerVLC をアンインストールしました。"
            preserved_result="設定とメディアライブラリは保持されています。"
            no_dialog_error="グラフィカルダイアログを利用できません。--install または --uninstall を明示的に指定してください。"
            ;;
        ko*)
            install_label="PowerVLC 설치"
            update_label="PowerVLC 업데이트"
            uninstall_label="PowerVLC 제거"
            cancel_label="취소"
            close_label="닫기"
            launch_label="PowerVLC 실행"
            existing_prompt="PowerVLC가 이미 이 계정에 설치되어 있습니다.

수행할 작업을 선택하십시오."
            new_prompt="PowerVLC는 관리자 권한 없이 이 계정에만 설치됩니다.

계속하시겠습니까?"
            uninstall_prompt="PowerVLC를 제거하시겠습니까?

응용 프로그램이 이 계정에서 제거됩니다. 환경 설정과 미디어 라이브러리는 유지됩니다."
            installed_result="PowerVLC %s 설치를 완료했습니다."
            updated_result="PowerVLC %s 업데이트를 완료했습니다."
            available_result="이제 메뉴에서 응용 프로그램을 사용할 수 있습니다."
            uninstalled_result="PowerVLC를 제거했습니다."
            preserved_result="환경 설정과 미디어 라이브러리는 유지되었습니다."
            no_dialog_error="그래픽 대화 상자를 사용할 수 없습니다. --install 또는 --uninstall을 명시적으로 사용하십시오."
            ;;
        nl*)
            install_label="PowerVLC installeren"
            update_label="PowerVLC bijwerken"
            uninstall_label="PowerVLC verwijderen"
            cancel_label="Annuleren"
            close_label="Sluiten"
            launch_label="PowerVLC starten"
            existing_prompt="PowerVLC is al voor uw account geïnstalleerd.

Kies de gewenste actie."
            new_prompt="PowerVLC wordt alleen voor uw account geïnstalleerd, zonder beheerdersrechten.

Wilt u doorgaan?"
            uninstall_prompt="PowerVLC verwijderen?

De toepassing wordt uit uw account verwijderd. Uw voorkeuren en mediabibliotheek blijven behouden."
            installed_result="PowerVLC %s is geïnstalleerd."
            updated_result="PowerVLC %s is bijgewerkt."
            available_result="De toepassing is nu beschikbaar in het menu."
            uninstalled_result="PowerVLC is verwijderd."
            preserved_result="Uw voorkeuren en mediabibliotheek zijn behouden."
            no_dialog_error="Er is geen grafisch dialoogvenster beschikbaar. Gebruik --install of --uninstall expliciet."
            ;;
        pl*)
            install_label="Zainstaluj PowerVLC"
            update_label="Zaktualizuj PowerVLC"
            uninstall_label="Odinstaluj PowerVLC"
            cancel_label="Anuluj"
            close_label="Zamknij"
            launch_label="Uruchom PowerVLC"
            existing_prompt="PowerVLC jest już zainstalowany dla tego konta.

Wybierz działanie do wykonania."
            new_prompt="PowerVLC zostanie zainstalowany tylko dla tego konta, bez uprawnień administratora.

Czy chcesz kontynuować?"
            uninstall_prompt="Odinstalować PowerVLC?

Aplikacja zostanie usunięta z tego konta. Preferencje i biblioteka multimediów zostaną zachowane."
            installed_result="PowerVLC %s został pomyślnie zainstalowany."
            updated_result="PowerVLC %s został pomyślnie zaktualizowany."
            available_result="Aplikacja jest teraz dostępna w menu."
            uninstalled_result="PowerVLC został odinstalowany."
            preserved_result="Preferencje i biblioteka multimediów zostały zachowane."
            no_dialog_error="Brak graficznego okna dialogowego. Użyj jawnie opcji --install lub --uninstall."
            ;;
        pt_BR*)
            install_label="Instalar o PowerVLC"
            update_label="Atualizar o PowerVLC"
            uninstall_label="Desinstalar o PowerVLC"
            cancel_label="Cancelar"
            close_label="Fechar"
            launch_label="Iniciar o PowerVLC"
            existing_prompt="O PowerVLC já está instalado para a sua conta.

Escolha a ação que deseja executar."
            new_prompt="O PowerVLC será instalado somente para a sua conta, sem privilégios de administrador.

Deseja continuar?"
            uninstall_prompt="Desinstalar o PowerVLC?

O aplicativo será removido da sua conta. Suas preferências e biblioteca de mídia serão preservadas."
            installed_result="O PowerVLC %s foi instalado com sucesso."
            updated_result="O PowerVLC %s foi atualizado com sucesso."
            available_result="O aplicativo agora está disponível no menu."
            uninstalled_result="O PowerVLC foi desinstalado."
            preserved_result="Suas preferências e biblioteca de mídia foram preservadas."
            no_dialog_error="Nenhuma caixa de diálogo gráfica está disponível. Use --install ou --uninstall explicitamente."
            ;;
        pt*)
            install_label="Instalar o PowerVLC"
            update_label="Atualizar o PowerVLC"
            uninstall_label="Desinstalar o PowerVLC"
            cancel_label="Cancelar"
            close_label="Fechar"
            launch_label="Iniciar o PowerVLC"
            existing_prompt="O PowerVLC já está instalado para a sua conta.

Escolha a ação a executar."
            new_prompt="O PowerVLC será instalado apenas para a sua conta, sem privilégios de administrador.

Deseja continuar?"
            uninstall_prompt="Desinstalar o PowerVLC?

A aplicação será removida da sua conta. As suas preferências e a biblioteca multimédia serão preservadas."
            installed_result="O PowerVLC %s foi instalado com êxito."
            updated_result="O PowerVLC %s foi atualizado com êxito."
            available_result="A aplicação está agora disponível no menu."
            uninstalled_result="O PowerVLC foi desinstalado."
            preserved_result="As suas preferências e a biblioteca multimédia foram preservadas."
            no_dialog_error="Não está disponível nenhuma caixa de diálogo gráfica. Utilize explicitamente --install ou --uninstall."
            ;;
        ru*)
            install_label="Установить PowerVLC"
            update_label="Обновить PowerVLC"
            uninstall_label="Удалить PowerVLC"
            cancel_label="Отмена"
            close_label="Закрыть"
            launch_label="Запустить PowerVLC"
            existing_prompt="PowerVLC уже установлен для вашей учётной записи.

Выберите действие."
            new_prompt="PowerVLC будет установлен только для вашей учётной записи, без прав администратора.

Продолжить?"
            uninstall_prompt="Удалить PowerVLC?

Приложение будет удалено из вашей учётной записи. Настройки и медиатека будут сохранены."
            installed_result="PowerVLC %s успешно установлен."
            updated_result="PowerVLC %s успешно обновлён."
            available_result="Приложение теперь доступно в меню."
            uninstalled_result="PowerVLC удалён."
            preserved_result="Настройки и медиатека сохранены."
            no_dialog_error="Графический диалог недоступен. Явно укажите --install или --uninstall."
            ;;
        sv*)
            install_label="Installera PowerVLC"
            update_label="Uppdatera PowerVLC"
            uninstall_label="Avinstallera PowerVLC"
            cancel_label="Avbryt"
            close_label="Stäng"
            launch_label="Starta PowerVLC"
            existing_prompt="PowerVLC är redan installerat för ditt konto.

Välj vilken åtgärd som ska utföras."
            new_prompt="PowerVLC installeras endast för ditt konto, utan administratörsbehörighet.

Vill du fortsätta?"
            uninstall_prompt="Avinstallera PowerVLC?

Programmet tas bort från ditt konto. Dina inställningar och ditt mediebibliotek bevaras."
            installed_result="PowerVLC %s har installerats."
            updated_result="PowerVLC %s har uppdaterats."
            available_result="Programmet finns nu i menyn."
            uninstalled_result="PowerVLC har avinstallerats."
            preserved_result="Dina inställningar och ditt mediebibliotek har bevarats."
            no_dialog_error="Ingen grafisk dialogruta är tillgänglig. Använd --install eller --uninstall uttryckligen."
            ;;
        tr*)
            install_label="PowerVLC'yi Kur"
            update_label="PowerVLC'yi Güncelle"
            uninstall_label="PowerVLC'yi Kaldır"
            cancel_label="İptal"
            close_label="Kapat"
            launch_label="PowerVLC'yi Başlat"
            existing_prompt="PowerVLC hesabınız için zaten kurulu.

Gerçekleştirilecek işlemi seçin."
            new_prompt="PowerVLC, yönetici ayrıcalıkları olmadan yalnızca hesabınız için kurulacak.

Devam etmek istiyor musunuz?"
            uninstall_prompt="PowerVLC kaldırılsın mı?

Uygulama hesabınızdan kaldırılacak. Tercihleriniz ve ortam kitaplığınız korunacak."
            installed_result="PowerVLC %s başarıyla kuruldu."
            updated_result="PowerVLC %s başarıyla güncellendi."
            available_result="Uygulama artık menüden kullanılabilir."
            uninstalled_result="PowerVLC kaldırıldı."
            preserved_result="Tercihleriniz ve ortam kitaplığınız korundu."
            no_dialog_error="Grafik iletişim kutusu kullanılamıyor. --install veya --uninstall seçeneğini açıkça kullanın."
            ;;
        uk*)
            install_label="Установити PowerVLC"
            update_label="Оновити PowerVLC"
            uninstall_label="Видалити PowerVLC"
            cancel_label="Скасувати"
            close_label="Закрити"
            launch_label="Запустити PowerVLC"
            existing_prompt="PowerVLC уже встановлено для вашого облікового запису.

Виберіть потрібну дію."
            new_prompt="PowerVLC буде встановлено лише для вашого облікового запису, без прав адміністратора.

Продовжити?"
            uninstall_prompt="Видалити PowerVLC?

Програму буде видалено з вашого облікового запису. Налаштування та медіатеку буде збережено."
            installed_result="PowerVLC %s успішно встановлено."
            updated_result="PowerVLC %s успішно оновлено."
            available_result="Програма тепер доступна в меню."
            uninstalled_result="PowerVLC видалено."
            preserved_result="Налаштування та медіатеку збережено."
            no_dialog_error="Графічне діалогове вікно недоступне. Явно вкажіть --install або --uninstall."
            ;;
        zh_CN*|zh_SG*)
            install_label="安装 PowerVLC"
            update_label="更新 PowerVLC"
            uninstall_label="卸载 PowerVLC"
            cancel_label="取消"
            close_label="关闭"
            launch_label="启动 PowerVLC"
            existing_prompt="已为您的账户安装 PowerVLC。

请选择要执行的操作。"
            new_prompt="PowerVLC 将仅为您的账户安装，无需管理员权限。

是否继续？"
            uninstall_prompt="是否卸载 PowerVLC？

该应用将从您的账户中移除。您的首选项和媒体库将会保留。"
            installed_result="PowerVLC %s 已成功安装。"
            updated_result="PowerVLC %s 已成功更新。"
            available_result="现在可以从菜单中打开该应用。"
            uninstalled_result="PowerVLC 已卸载。"
            preserved_result="您的首选项和媒体库已保留。"
            no_dialog_error="没有可用的图形对话框。请明确使用 --install 或 --uninstall。"
            ;;
        zh_TW*|zh_HK*|zh_MO*)
            install_label="安裝 PowerVLC"
            update_label="更新 PowerVLC"
            uninstall_label="解除安裝 PowerVLC"
            cancel_label="取消"
            close_label="關閉"
            launch_label="啟動 PowerVLC"
            existing_prompt="已為您的帳號安裝 PowerVLC。

請選擇要執行的動作。"
            new_prompt="PowerVLC 將只為您的帳號安裝，不需要管理員權限。

是否繼續？"
            uninstall_prompt="是否解除安裝 PowerVLC？

此應用程式將從您的帳號中移除。您的偏好設定與媒體庫將會保留。"
            installed_result="PowerVLC %s 已成功安裝。"
            updated_result="PowerVLC %s 已成功更新。"
            available_result="現在可以從選單開啟此應用程式。"
            uninstalled_result="PowerVLC 已解除安裝。"
            preserved_result="您的偏好設定與媒體庫已保留。"
            no_dialog_error="沒有可用的圖形對話框。請明確使用 --install 或 --uninstall。"
            ;;
    esac
}
