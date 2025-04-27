import React, { Fragment } from 'react';
import Button from './Button'; // Assuming Button is in the same directory

interface ModalProps {
  isOpen: boolean;
  onClose: () => void;
  title: string;
  children: React.ReactNode;
  confirmText?: string;
  onConfirm?: () => void;
  cancelText?: string;
  onCancel?: () => void; // Can default to onClose if not provided
}

const Modal: React.FC<ModalProps> = ({
  isOpen,
  onClose,
  title,
  children,
  confirmText = 'Confirm',
  onConfirm,
  cancelText = 'Cancel',
  onCancel,
}) => {
  if (!isOpen) return null;

  const handleCancel = onCancel || onClose;

  return (
    // Using Fragment might cause issues with libraries expecting a single root node for transitions, 
    // consider a div wrapper if using transition libraries. For basic modal, Fragment is fine.
    <Fragment>
        {/* Backdrop */}
        <div 
          className="fixed inset-0 bg-gray-500 bg-opacity-75 transition-opacity z-40" 
          aria-hidden="true"
          onClick={onClose} // Close on backdrop click
        ></div>

        {/* Modal Panel */}
        <div className="fixed inset-0 z-50 overflow-y-auto">
            <div className="flex min-h-full items-center justify-center p-4 text-center">
                <div className="relative transform overflow-hidden rounded-lg bg-white text-left shadow-xl transition-all sm:my-8 sm:w-full sm:max-w-lg">
                    <div className="bg-white px-4 pb-4 pt-5 sm:p-6 sm:pb-4">
                        <div className="sm:flex sm:items-start">
                            {/* Optional: Icon can go here */}
                            {/* <div className="mx-auto flex h-12 w-12 flex-shrink-0 items-center justify-center rounded-full bg-blue-100 sm:mx-0 sm:h-10 sm:w-10"> */}
                                {/* Icon SVG */}
                            {/* </div> */}
                            <div className="mt-3 text-center sm:ml-4 sm:mt-0 sm:text-left w-full">
                                <h3 className="text-lg font-semibold leading-6 text-gray-900" id="modal-title">
                                    {title}
                                </h3>
                                <div className="mt-2">
                                    <div className="text-sm text-gray-500">
                                        {children}
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>
                    <div className="bg-gray-50 px-4 py-3 sm:flex sm:flex-row-reverse sm:px-6">
                        {onConfirm && (
                            <Button 
                                variant="primary" 
                                onClick={onConfirm} 
                                className="sm:ml-3 w-full sm:w-auto"
                            >
                                {confirmText}
                            </Button>
                        )}
                        <Button 
                            variant="secondary" 
                            onClick={handleCancel} 
                            className="mt-3 w-full sm:mt-0 sm:w-auto"
                        >
                            {cancelText}
                        </Button>
                    </div>
                </div>
            </div>
        </div>
    </Fragment>
  );
};

export default Modal;
