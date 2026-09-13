import React, { forwardRef } from 'react';
import { Form } from 'formik';
import styled from 'styled-components/macro';
import { breakpoint } from '@/theme';
import FlashMessageRender from '@/components/FlashMessageRender';
import tw from 'twin.macro';

type Props = React.DetailedHTMLProps<React.FormHTMLAttributes<HTMLFormElement>, HTMLFormElement> & {
    title?: string;
};

const Container = styled.div`
    ${breakpoint('sm')`
        ${tw`w-4/5 mx-auto`}
    `};

    ${breakpoint('md')`
        ${tw`p-10`}
    `};

    ${breakpoint('lg')`
        ${tw`w-3/5`}
    `};

    ${breakpoint('xl')`
        ${tw`w-full`}
        max-width: 760px;
    `};
`;

const LoginCard = styled.div`
    position: relative;
    display: flex;
    overflow: hidden;
    border: 1px solid rgba(148, 163, 184, .16);
    border-radius: 24px;
    background: rgba(255, 255, 255, .96);
    box-shadow: 0 30px 80px rgba(15, 23, 42, .28), 0 8px 24px rgba(15, 23, 42, .10);
    backdrop-filter: blur(18px);

    &::before {
        content: '';
        position: absolute;
        inset: 0;
        pointer-events: none;
        background: linear-gradient(135deg, rgba(139, 92, 246, .07), transparent 42%, rgba(37, 99, 235, .06));
    }
`;

const BrandPanel = styled.div`
    position: relative;
    display: flex;
    width: 40%;
    min-width: 220px;
    align-items: center;
    justify-content: center;
    padding: 44px 28px;
    background: linear-gradient(145deg, #0b1020 0%, #151d35 58%, #1d2850 100%);

    &::after {
        content: '';
        position: absolute;
        width: 190px;
        height: 190px;
        border-radius: 999px;
        background: linear-gradient(135deg, rgba(139, 92, 246, .30), rgba(37, 99, 235, .08));
        filter: blur(2px);
    }
`;

const FormPanel = styled.div`
    position: relative;
    z-index: 1;
    flex: 1;
    padding: 34px 34px 30px;

    @media (max-width: 767px) {
        padding: 28px 24px;
    }
`;

export default forwardRef<HTMLFormElement, Props>(({ title, ...props }, ref) => (
    <Container>
        <FlashMessageRender css={tw`mb-4 px-1`} />
        <Form {...props} ref={ref}>
            <LoginCard>
                <BrandPanel css={tw`hidden md:flex flex-col`}>
                    <div css={tw`relative z-10 flex flex-col items-center text-center`}>
                        <img
                            src={'/assets/svgs/nxdactyl.svg'}
                            alt={'Nx Panel'}
                            css={tw`block w-32 lg:w-40 h-auto mb-5`}
                        />
                        <div css={tw`text-white text-xl font-semibold tracking-tight`}>Nx Panel</div>
                        <div css={tw`text-gray-400 text-xs mt-2 tracking-wide uppercase`}>Game server control</div>
                    </div>
                </BrandPanel>
                <FormPanel>
                    <div css={tw`mb-7`}>
                        <div css={tw`text-xs font-semibold uppercase tracking-widest text-violet-500 mb-2`}>Welcome back</div>
                        {title && <h2 css={tw`text-3xl text-gray-900 font-bold tracking-tight`}>{title}</h2>}
                        <p css={tw`text-sm text-gray-500 mt-2`}>Sign in to manage your servers and infrastructure.</p>
                    </div>
                    {props.children}
                </FormPanel>
            </LoginCard>
        </Form>
        <p css={tw`text-center text-gray-500 text-xs mt-5`}>
            &copy; 2015 - {new Date().getFullYear()}&nbsp;
            <span> Nx Panel · NXDactyl </span>
        </p>
    </Container>
));
