(function () {
  const store = new Map();

  function readOption(scope, key) {
    return store.get(`${scope}:${key}`) || '';
  }

  window.getByName = function (name, arg) {
    switch (name) {
      case 'app-name':
        return 'RustDesk Harness';
      case 'version':
        return 'dev';
      case 'build_date':
        return 'dev';
      case 'local_os':
        return 'web';
      case 'platform':
        return 'web';
      case 'screen_info':
        return '';
      case 'translate': {
        try {
          const parsed = JSON.parse(arg || '{}');
          return parsed.text || '';
        } catch (_) {
          return '';
        }
      }
      case 'option':
      case 'option:local':
      case 'option:flutter:local':
      case 'envvar':
        return readOption(name, arg || '');
      case 'options':
        return '{}';
      case 'fav':
      case 'langs':
        return '[]';
      case 'my_id':
      case 'uuid':
        return 'dashboard-harness';
      case 'get_conn_status':
        return 'disconnected';
      case 'is_using_public_server':
      case 'enable_trusted_devices':
      case 'remember':
        return 'false';
      default:
        return '';
    }
  };

  window.setByName = function (name, value) {
    if (!value) return '';
    try {
      const parsed = JSON.parse(value);
      if (parsed && parsed.name) {
        store.set(`${name}:${parsed.name}`, parsed.value || '');
      }
    } catch (_) {
      store.set(`${name}:value`, value);
    }
    return '';
  };

  window.init = function () {
    if (typeof window.onInitFinished === 'function') {
      window.onInitFinished();
    }
  };
})();
