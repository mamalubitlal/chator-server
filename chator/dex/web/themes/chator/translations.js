// чатор Russian Translation Overlay for Dex
// This script runs after Dex page loads and translates UI to Russian

(function() {
  'use strict';

  const translations = {
    // Login page
    'Sign in to your Account': 'Вход в аккаунт',
    'Sign In': 'Войти',
    'Email Address': 'Email',
    'Password': 'Пароль',
    'Remember me': 'Запомнить меня',
    'Invalid email address': 'Неверный email',
    'Invalid password': 'Неверный пароль',
    'Invalid email or password': 'Неверный email или пароль',
    
    // Consent page
    'Grant Access': 'Предоставить доступ',
    'has requested access to your account': 'запрашивает доступ к вашему аккаунту',
    'at': 'в',
    'This application will be able to': 'Это приложение сможет:',
    'View your profile': 'Просматривать ваш профиль',
    'View your email address': 'Просматривать ваш email',
    'I understand': 'Я понимаю',
    
    // Error messages
    'Error': 'Ошибка',
    'Bad Request': 'Неверный запрос',
    'Unauthorized': 'Не авторизован',
    'Server Error': 'Ошибка сервера',
    
    // Common
    'Loading...': 'Загрузка...',
    'Submit': 'Отправить',
    'Cancel': 'Отмена',
    'Back': 'Назад',
    'Continue': 'Продолжить',
    
    // чатор specific
    'чатор Login': 'Вход через чатор',
    'Matrix Synapse': 'Matrix Synapse',
  };

  function translatePage() {
    // Translate text nodes
    const walker = document.createTreeWalker(
      document.body,
      NodeFilter.SHOW_TEXT,
      null,
      false
    );

    const nodesToTranslate = [];
    let node;
    while (node = walker.nextNode()) {
      const text = node.textContent.trim();
      if (translations[text]) {
        nodesToTranslate.push({ node, text });
      }
    }

    nodesToTranslate.forEach(({ node, text }) => {
      node.textContent = node.textContent.replace(text, translations[text]);
    });

    // Translate placeholders
    document.querySelectorAll('input[placeholder]').forEach(input => {
      const placeholder = input.getAttribute('placeholder');
      if (translations[placeholder]) {
        input.setAttribute('placeholder', translations[placeholder]);
      }
    });

    // Translate titles
    document.querySelectorAll('[title]').forEach(el => {
      const title = el.getAttribute('title');
      if (translations[title]) {
        el.setAttribute('title', translations[title]);
      }
    });

    // Add чатор branding
    const panel = document.querySelector('.theme-form-panel');
    if (panel) {
      const title = panel.querySelector('h2');
      if (title && title.textContent.includes('Sign in')) {
        title.textContent = 'Вход в чатор';
      }
    }

    console.log('[чатор] Russian translation applied');
  }

  // Run when DOM is ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', translatePage);
  } else {
    translatePage();
  }
})();
